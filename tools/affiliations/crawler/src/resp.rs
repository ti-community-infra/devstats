use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct Resp<D> {
    pub(crate) code: i64,
    pub(crate) msg: String,
    pub(crate) data: D,
}

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct Data<T> {
    pub(crate) has_more: bool,
    pub(crate) page_token: Option<String>,
    pub(crate) items: Option<Vec<T>>,
}
