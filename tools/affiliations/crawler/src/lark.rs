use crate::auth::AuthResp;
use crate::resp::{Data, Resp};
use anyhow::{anyhow, Result};
use reqwest::Client;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub struct AppConfig {
    pub app_id: String,
    pub app_secret: String,
}

const DEFAULT_HOST: &str = "https://open.feishu.cn/open-apis";

pub struct Lark {
    pub host: String,
    pub client: Client,
    pub config: AppConfig,
}

impl Lark {
    pub fn new(config: AppConfig) -> Result<Self> {
        Self::host(DEFAULT_HOST, config)
    }

    pub fn host<H>(host: H, config: AppConfig) -> Result<Self>
    where
        H: Into<String>,
    {
        let http = Client::builder().build()?;
        {
            Ok(Self::custom(host, config, http))
        }
    }

    pub fn custom<H>(host: H, config: AppConfig, http: Client) -> Self
    where
        H: Into<String>,
    {
        Self {
            host: host.into(),
            config,
            client: http,
        }
    }

    fn url(&self, uri: &str) -> String {
        format!("{}/{}", &self.host, uri)
    }

    pub async fn auth(&self) -> Result<String> {
        Ok(self
            .client
            .post(self.url("auth/v3/tenant_access_token/internal/"))
            .json(&self.config)
            .send()
            .await?
            .json::<AuthResp>()
            .await?
            .tenant_access_token)
    }

    pub async fn list<R, A, P>(&self, uri: A, parameters: Option<&P>) -> Result<Vec<R>>
    where
        A: AsRef<str>,
        P: Serialize + ?Sized,
        R: DeserializeOwned,
    {
        let token = self.auth().await?;
        let mut results = vec![];
        let mut request = self.client.get(self.url(uri.as_ref())).bearer_auth(&token);

        if let Some(parameters) = parameters {
            request = request.query(parameters);
        }

        let mut res = request.send().await?.json::<Resp<Data<R>>>().await?;
        if res.code != 0 {
            return Err(anyhow!("List failed and msg is {}", res.msg));
        }
        if let Some(items) = res.data.items {
            results.extend(items);
        }

        while let Some(ref page_token) = res.data.page_token {
            let mut request = self.client.get(self.url(uri.as_ref())).bearer_auth(&token);

            if let Some(parameters) = parameters {
                request = request.query(parameters);
            }
            request = request.query(&[("page_token", page_token)]);

            res = request.send().await?.json::<Resp<Data<R>>>().await?;
            if res.code != 0 {
                return Err(anyhow!("List failed and msg is {}", res.msg));
            }
            if let Some(items) = res.data.items {
                results.extend(items);
            }
        }

        Ok(results)
    }
}
