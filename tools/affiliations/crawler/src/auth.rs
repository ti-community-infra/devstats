use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct AuthResp {
    pub(crate) code: i64,
    pub(crate) msg: String,
    pub(crate) tenant_access_token: String,
}
