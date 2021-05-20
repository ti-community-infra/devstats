use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub struct AuthResp {
    pub code: i64,
    pub msg: String,
    pub tenant_access_token: String,
}
