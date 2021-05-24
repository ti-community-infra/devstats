use crawler::crawler::Crawler;
use serde::Deserialize;

#[derive(Deserialize, Debug)]
struct Config {
    url: String,
    app_id: String,
    app_secret: String,
}

#[tokio::main]
async fn main() {
    match envy::from_env::<Config>() {
        Ok(config) => {
            let crawler = &Crawler::new(config.app_id, config.app_secret).expect("Failed init");
            match crawler.list_github_logins().await {
                Ok(names) => names.iter().for_each(|n| println!("{}", n)),
                Err(error) => panic!("{:#?}", error),
            }
        }
        Err(error) => panic!("{:#?}", error),
    }
}
