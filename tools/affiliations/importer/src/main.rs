#[macro_use]
extern crate dotenv_codegen;

use crawler::crawler::{Crawl, Crawler};

#[tokio::main]
async fn main() {
    let crawler = &Crawler::new(dotenv!("APP_ID").to_string(), dotenv!("APP_SECRET").to_string()).expect("Failed init");
    match crawler.list_github_logins().await {
        Ok(names) => names.iter().for_each(|n| println!("{}", n)),
        Err(error) => panic!("{:#?}", error),
    }
}
