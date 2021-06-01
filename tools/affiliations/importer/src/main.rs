#[macro_use]
extern crate dotenv_codegen;

use crawler::crawler::{Crawl, Crawler};
use diesel::prelude::*;
use importer::establish_connection;
use importer::models::GhaActor;
use importer::schema::gha_actors::columns::login;
use importer::schema::gha_actors::dsl::gha_actors;

#[tokio::main]
async fn main() {
    pretty_env_logger::init();
    let connection = establish_connection();

    let crawler =
        &Crawler::new(dotenv!("APP_ID"), dotenv!("APP_SECRET")).expect("Failed init the crawler.");
    match crawler.list_github_logins().await {
        Ok(logins) => logins.iter().for_each(|l| {
            match gha_actors
                .filter(login.eq(l))
                .first::<GhaActor>(&connection)
            {
                Ok(actor) => {
                    println!("{}", actor.login);
                }
                Err(_) => {
                    println!("{} not found", l)
                }
            }
        }),
        Err(error) => panic!("{:#?}", error),
    }
}
