/*-------------------------------------------------------------------------
 * Copyright (c) Microsoft Corporation.  All rights reserved.
 *
 * documentdb_gateway_core/src/processor/session.rs
 *
 *-------------------------------------------------------------------------
 */

use bson::RawArray;

use crate::{
    context::{ConnectionContext, LogicalSessionId, RequestContext},
    error::{DocumentDBError, ErrorCode, Result},
    postgres::PgDataClient,
    requests::RequestType,
    responses::Response,
};

const ADMIN_DB: &str = "admin";

fn parse_logical_session_ids(sessions_field: &RawArray) -> Result<Vec<LogicalSessionId>> {
    let mut logical_session_ids = Vec::new();
    for session in sessions_field {
        let session_doc = session?
            .as_document()
            .ok_or_else(|| DocumentDBError::bad_value("Session should be a document".to_owned()))?;

        let lsid = LogicalSessionId::from(
            session_doc
                .get_binary("id")
                .map_err(DocumentDBError::parse_failure())?
                .bytes,
        );

        logical_session_ids.push(lsid);
    }
    Ok(logical_session_ids)
}

async fn terminate_sessions(
    request_context: &RequestContext<'_>,
    connection_context: &ConnectionContext,
    pg_data_client: &impl PgDataClient,
    sessions_field: &RawArray,
) -> Result<()> {
    let logical_session_ids = parse_logical_session_ids(sessions_field)?;
    let caller = connection_context.auth_state.principal()?;
    let transaction_store = connection_context.service_context.transaction_store();

    for lsid in &logical_session_ids {
        // Remove all cursors for the session
        let cursor_ids = connection_context
            .service_context
            .cursor_store()
            .invalidate_cursors_by_session(lsid);

        if !cursor_ids.is_empty() {
            if let Err(e) = pg_data_client
                .execute_kill_cursors(request_context, connection_context, &cursor_ids)
                .await
            {
                tracing::warn!("Error killing cursors for session {:?}: {}", lsid, e);
            }
        }

        // Best effort to remove any transaction for the session
        let _ = transaction_store
            .remove_transaction_by_session(lsid, caller)
            .await?;
    }

    Ok(())
}

pub async fn end_or_kill_sessions(
    request_context: &RequestContext<'_>,
    connection_context: &ConnectionContext,
    pg_data_client: &impl PgDataClient,
) -> Result<Response> {
    let request = request_context.payload;

    let key = if request_context.payload.request_type() == RequestType::KillSessions {
        "killSessions"
    } else {
        "endSessions"
    };

    let sessions_field = request
        .document()
        .get_array(key)
        .map_err(DocumentDBError::parse_failure())?;

    terminate_sessions(
        request_context,
        connection_context,
        pg_data_client,
        sessions_field,
    )
    .await?;

    Ok(Response::ok())
}

fn parse_kill_all_sessions_users(users_field: &RawArray) -> Result<Option<Vec<String>>> {
    let mut users: Vec<String> = Vec::new();

    for user in users_field {
        let user_doc = user?.as_document().ok_or_else(|| {
            DocumentDBError::bad_value("Each killAllSessions entry should be a document".to_owned())
        })?;

        let username = user_doc
            .get_str("user")
            .map_err(DocumentDBError::parse_failure())?;
        let db = user_doc
            .get_str("db")
            .map_err(DocumentDBError::parse_failure())?;

        // Gateway principals are authenticated against the admin database;
        // patterns scoped to any other database cannot match a session.
        if db == ADMIN_DB && !users.iter().any(|user| user == username) {
            users.push(username.to_owned());
        }
    }

    Ok((!users.is_empty()).then_some(users))
}

async fn kill_sessions_matching_users(
    request_context: &RequestContext<'_>,
    connection_context: &ConnectionContext,
    pg_data_client: &impl PgDataClient,
    users: Option<&[String]>,
) -> Result<()> {
    let cursor_store = connection_context.service_context.cursor_store();
    let transaction_store = connection_context.service_context.transaction_store();

    let mut cursor_ids = if let Some(users) = users {
        let mut cursor_ids = Vec::new();
        for username in users {
            cursor_ids.extend(cursor_store.invalidate_cursors_by_owner_name(username));
        }

        let _ = transaction_store
            .remove_transactions_by_owner_names(users)
            .await?;

        cursor_ids
    } else {
        let cursor_ids = cursor_store.invalidate_all_cursors();

        let _ = transaction_store.remove_all_transactions().await?;

        cursor_ids
    };

    cursor_ids.sort_unstable();
    cursor_ids.dedup();

    if !cursor_ids.is_empty() {
        if let Err(e) = pg_data_client
            .execute_kill_cursors(request_context, connection_context, &cursor_ids)
            .await
        {
            tracing::warn!("Error killing cursors during killAllSessions: {}", e);
        }
    }

    Ok(())
}

pub async fn kill_all_sessions(
    request_context: &RequestContext<'_>,
    connection_context: &ConnectionContext,
    pg_data_client: &impl PgDataClient,
) -> Result<Response> {
    // Validate that the command is run against the admin database
    if request_context.info.db()? != ADMIN_DB {
        return Err(DocumentDBError::documentdb_error(
            ErrorCode::Unauthorized,
            "killAllSessions may only be run against the admin database.".to_owned(),
            0,
        ));
    }

    let users_field = request_context
        .payload
        .document()
        .get_array("killAllSessions")
        .map_err(DocumentDBError::parse_failure())?;

    let users = parse_kill_all_sessions_users(users_field)?;

    kill_sessions_matching_users(
        request_context,
        connection_context,
        pg_data_client,
        users.as_deref(),
    )
    .await?;

    Ok(Response::ok())
}

#[cfg(test)]
mod tests {
    use bson::rawdoc;

    use super::parse_kill_all_sessions_users;

    #[test]
    fn parse_kill_all_sessions_empty_array_returns_none() {
        let request = rawdoc! {
            "killAllSessions": []
        };

        let users = parse_kill_all_sessions_users(
            request
                .get_array("killAllSessions")
                .expect("killAllSessions should be an array"),
        )
        .expect("killAllSessions parsing should succeed");

        assert!(users.is_none(), "empty array should target all sessions");
    }

    #[test]
    fn parse_kill_all_sessions_users_returns_admin_db_users() {
        let request = rawdoc! {
            "killAllSessions": [
                { "user": "alice", "db": "admin" },
                { "user": "bob", "db": "admin" },
                { "user": "carol", "db": "otherdb" }
            ]
        };

        let users = parse_kill_all_sessions_users(
            request
                .get_array("killAllSessions")
                .expect("killAllSessions should be an array"),
        )
        .expect("killAllSessions parsing should succeed")
        .expect("killAllSessions should contain user patterns");

        assert!(users.iter().any(|user| user == "alice"));
        assert!(users.iter().any(|user| user == "bob"));
        assert!(
            !users.iter().any(|user| user == "carol"),
            "non-admin db patterns cannot match gateway sessions"
        );
        assert_eq!(users.len(), 2);
    }

    #[test]
    fn parse_kill_all_sessions_rejects_non_document_entries() {
        let request = rawdoc! {
            "killAllSessions": [ "alice" ]
        };

        let users = parse_kill_all_sessions_users(
            request
                .get_array("killAllSessions")
                .expect("killAllSessions should be an array"),
        );

        assert!(users.is_err(), "non-document entries should be rejected");
    }
}
