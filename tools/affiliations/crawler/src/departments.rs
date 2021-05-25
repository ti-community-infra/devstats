use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct Department {
    pub(crate) open_department_id: String,
}
