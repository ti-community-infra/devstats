use chrono::NaiveDateTime;

#[derive(Queryable)]
pub struct GhaActor {
    pub id: i64,
    pub login: String,
    pub name: Option<String>,
    pub country_id: Option<String>,
    pub sex: Option<String>,
    pub sex_prob: Option<f64>,
    pub tz: Option<String>,
    pub tz_offset: Option<i32>,
    pub country_name: Option<String>,
    pub age: Option<i32>,
}

#[derive(Queryable)]
pub struct GhaActorAffiliation {
    pub actor_id: i64,
    pub company_name: String,
    pub original_company_name: String,
    pub dt_from: NaiveDateTime,
    pub dt_to: NaiveDateTime,
    pub source: String,
}
