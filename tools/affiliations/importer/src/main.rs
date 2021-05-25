extern crate pretty_env_logger;

#[macro_use]
extern crate dotenv_codegen;

use crawler::crawler::{Crawl, Crawler};

#[tokio::main]
async fn main() {
    pretty_env_logger::init();
    let crawler =
        &Crawler::new(dotenv!("APP_ID"), dotenv!("APP_SECRET")).expect("Failed init the crawler.");
    match crawler.list_github_logins().await {
        Ok(names) => names.iter().for_each(|n| println!("{}", n)),
        Err(error) => panic!("{:#?}", error),
    }
}
