use serde::{Deserialize, Serialize};

pub(crate) const GITHUB_LOGIN_ATTR_ID: &str = "C-6934211695879389211";

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct User {
    pub(crate) custom_attrs: Option<Vec<CustomAttrs>>,
}

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct CustomAttrs {
    pub(crate) id: String,
    pub(crate) value: Value,
}

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct Value {
    pub(crate) text: String,
}
