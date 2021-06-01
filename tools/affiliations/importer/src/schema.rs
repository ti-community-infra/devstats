table! {
    gha_actors (id, login) {
        id -> Int8,
        login -> Varchar,
        name -> Nullable<Varchar>,
        country_id -> Nullable<Varchar>,
        sex -> Nullable<Varchar>,
        sex_prob -> Nullable<Float8>,
        tz -> Nullable<Varchar>,
        tz_offset -> Nullable<Int4>,
        country_name -> Nullable<Text>,
        age -> Nullable<Int4>,
    }
}

table! {
    gha_actors_affiliations (actor_id, company_name, dt_from, dt_to) {
        actor_id -> Int8,
        company_name -> Varchar,
        original_company_name -> Varchar,
        dt_from -> Timestamp,
        dt_to -> Timestamp,
        source -> Varchar,
    }
}

allow_tables_to_appear_in_same_query!(gha_actors, gha_actors_affiliations,);
