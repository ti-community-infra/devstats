use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub struct Resp<D> {
    pub code: i64,
    pub msg: String,
    pub data: D,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Data<T> {
    pub has_more: bool,
    pub page_token: Option<String>,
    pub items: Option<Vec<T>>,
}
