use crate::auth::AuthResp;
use crate::resp::{Data, Resp};
use anyhow::{anyhow, Result};
use reqwest::Client;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

const DEFAULT_BASE_URL: &str = "https://open.feishu.cn/open-apis";

#[derive(Serialize, Deserialize, Debug)]
pub(crate) struct AppConfig {
    pub(crate) app_id: String,
    pub(crate) app_secret: String,
}

pub(crate) struct Lark {
    pub(crate) base_url: String,
    pub(crate) client: Client,
    pub(crate) config: AppConfig,
}

impl Lark {
    pub(crate) fn new(config: AppConfig) -> Result<Self> {
        Self::base_url(DEFAULT_BASE_URL, config)
    }

    pub(crate) fn base_url<H>(host: H, config: AppConfig) -> Result<Self>
    where
        H: Into<String>,
    {
        let http = Client::builder().build()?;
        {
            Ok(Self::custom(host, config, http))
        }
    }

    pub(crate) fn custom<H>(host: H, config: AppConfig, http: Client) -> Self
    where
        H: Into<String>,
    {
        Self {
            base_url: host.into(),
            config,
            client: http,
        }
    }

    fn url(&self, uri: &str) -> String {
        format!("{}/{}", &self.base_url, uri)
    }

    async fn auth(&self) -> Result<String> {
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

    pub(crate) async fn list<R, A, P>(&self, uri: A, parameters: Option<&P>) -> Result<Vec<R>>
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
        debug!("Request: {:?}", &request);

        let mut res = request
            .try_clone()
            .unwrap()
            .send()
            .await?
            .json::<Resp<Data<R>>>()
            .await?;
        if res.code != 0 {
            error!("Request failed and msg is {:?}", &res.msg);
            return Err(anyhow!("Request failed and msg is {}", &res.msg));
        }
        if let Some(items) = res.data.items {
            results.extend(items);
        }

        while let Some(ref page_token) = res.data.page_token {
            let request = request
                .try_clone()
                .unwrap()
                .query(&[("page_token", page_token)]);
            debug!("Request: {:?}", &request);

            res = request.send().await?.json::<Resp<Data<R>>>().await?;
            if res.code != 0 {
                error!("Request failed and msg is {:?}", &res.msg);
                return Err(anyhow!("Request failed and msg is {}", &res.msg));
            }
            if let Some(items) = res.data.items {
                results.extend(items);
            }
        }

        Ok(results)
    }
}
