use crate::auth::AuthResp;
use anyhow::Result;
use reqwest::Client;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::fmt;

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

    /// Send a `GET` request to `uri` with optional query parameters, returning
    /// the body of the response.
    pub async fn get<R, T, A, P>(&self, token: T, uri: A, parameters: Option<&P>) -> Result<R>
    where
        A: AsRef<str>,
        T: fmt::Display,
        P: Serialize + ?Sized,
        R: DeserializeOwned,
    {
        let mut request = self.client.get(self.url(uri.as_ref())).bearer_auth(token);

        if let Some(parameters) = parameters {
            request = request.query(parameters);
        }

        Ok(request.send().await?.json::<R>().await?)
    }
}
