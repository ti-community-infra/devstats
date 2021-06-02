#[macro_use]
extern crate dotenv_codegen;

use crawler::crawler::{Crawl, Crawler};
use diesel::prelude::*;
use importer::establish_connection;
use importer::schema::gha_actors::columns::{id, login};
use importer::schema::gha_actors::dsl::gha_actors;
use importer::schema::gha_actors_affiliations::columns::{actor_id, company_name};
use importer::schema::gha_actors_affiliations::dsl::gha_actors_affiliations;

#[tokio::main]
async fn main() {
    pretty_env_logger::init();
    let connection = establish_connection();

    let crawler =
        &Crawler::new(dotenv!("APP_ID"), dotenv!("APP_SECRET")).expect("Failed init the crawler.");
    match crawler.list_github_logins().await {
        Ok(logins) => logins.iter().for_each(|l| {
            let companies = gha_actors
                .inner_join(gha_actors_affiliations.on(actor_id.eq(id)))
                .filter(login.eq(l))
                .select(company_name)
                .load::<String>(&connection);
            match companies {
                Ok(companies) => {
                    if companies.is_empty() {
                        println!("{} has no affiliation information yet.", l);
                    } else {
                        println!("{} affiliated with these companies: {:?}.", l, companies);
                    }
                }
                Err(_) => {
                    println!("List {} companies failed.", l)
                }
            }
        }),
        Err(error) => panic!("{:#?}", error),
    }
}
