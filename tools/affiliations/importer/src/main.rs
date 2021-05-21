use crawler::crawler::{AppConfig, Crawl, Crawler};
use serde::Deserialize;

#[derive(Deserialize, Debug)]
struct Config {
    url: String,
    app_id: String,
    app_secret: String,
}

fn main() {
    match envy::from_env::<Config>() {
        Ok(config) => {
            let crawler = &Crawler {
                api_url: config.url,
                config: AppConfig {
                    app_id: config.app_id,
                    app_secret: config.app_secret,
                },
                client: Default::default(),
            };
            match crawler.list_github_logins() {
                Ok(names) => names.iter().for_each(|n| println!("{}", n)),
                Err(error) => panic!("{:#?}", error),
            }
        }
        Err(error) => panic!("{:#?}", error),
    }
}
