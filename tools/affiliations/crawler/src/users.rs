use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub struct UsersResp {
    pub code: i64,
    pub msg: String,
    pub data: RespDetails,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct RespDetails {
    pub has_more: bool,
    pub page_token: Option<String>,
    pub items: Vec<User>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct User {
    pub custom_attrs: Vec<CustomAttrs>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct CustomAttrs {
    #[serde(rename = "type")]
    pub attr_type: String,
    pub id: String,
    pub value: Value,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Value {
    pub text: String,
    pub url: String,
    pub pc_url: String,
}
