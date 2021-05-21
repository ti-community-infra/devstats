use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub struct User {
    pub custom_attrs: Option<Vec<CustomAttrs>>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct CustomAttrs {
    pub id: String,
    pub value: Value,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Value {
    pub text: String,
}
