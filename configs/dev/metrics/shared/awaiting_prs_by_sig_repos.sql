with dtfrom as (
  select '{{to}}'::timestamp - '3 year'::interval as dtfrom
), issues as (
  -- select all pr related issue that still not be closed or merged.
  select
    distinct sub.issue_id,
    sub.event_id
  from (
    -- select all pr related issue that created in the 3 years.
    select
      distinct id as issue_id,
      last_value(event_id) over issues_ordered_by_update as event_id,
      last_value(closed_at) over issues_ordered_by_update as closed_at
    from
      gha_issues,
      dtfrom
    where
      created_at >= dtfrom
      and created_at < '{{to}}'
      and updated_at < '{{to}}'
      and is_pull_request = true
    window
      issues_ordered_by_update as (
        partition by id
        order by
          updated_at asc,
          event_id asc
        range between current row
        and unbounded following
      )
    ) sub
    where
      sub.closed_at is null
), prs as (
  -- select all pr that still not be closed or merged.
  select
    distinct i.issue_id,
    i.event_id
  from (
    -- select all pr that created in the 3 years.
    select
      distinct id as pr_id,
      last_value(closed_at) over prs_ordered_by_update as closed_at,
      last_value(merged_at) over prs_ordered_by_update as merged_at
    from
      gha_pull_requests,
      dtfrom
    where
      created_at >= dtfrom
      and created_at < '{{to}}'
      and updated_at < '{{to}}'
      and event_id > 0
    window
      prs_ordered_by_update as (
        partition by id
        order by
          updated_at asc,
          event_id asc
        range between current row
        and unbounded following
      )
    ) pr,
    issues i,
    gha_issues_pull_requests ipr
  where
    ipr.issue_id = i.issue_id
    and ipr.pull_request_id = pr.pr_id
    and pr.closed_at is null
    and pr.merged_at is null
), pr_sigs as (
  -- select all sig.
    select
      sub.issue_id,
      sub.event_id,
      sub.sig
    from (
      select
        pr.issue_id,
        pr.event_id,
        lower(substring(il.dup_label_name from '(?i)sig/(.*)')) as sig
      from
        gha_issues_labels il,
        prs pr
      where
        il.issue_id = pr.issue_id
        and il.event_id = pr.event_id
      ) sub
    where
      sub.sig is not null
      and sub.sig in (select sig_mentions_labels_name from tsig_mentions_labels)
), dtto as (
  select case '{{to}}'::timestamp > now() when true then now() else '{{to}}'::timestamp end as dtto
), prs_with_sig_labels as (
  select
    sig,
    repo,
    issue_id,
    age,
    case when author_login like any(array[
            'dependabot', 'ti-srebot', 'codecov-io', 'web-flow',  'prowbot', 'travis%bot', 'k8s-%', '%-bot',
            '%-robot', 'bot-%', 'robot-%', '%[bot]%', '%[robot]%', '%-jenkins', 'jenkins-%', '%-ci%bot', 
            '%-testing', 'codecov-%', '%clabot%', '%cla-bot%', '%-gerrit', '%-bot-%', '%cibot', '%-ci'
        ])
             then 'only-bots'
         when author_company = 'PingCAP'
             then 'is-top-contributing-company'
         else 'not-top-contributing-company'
    end author_type
  from (
    select s.sig,
        pr.dup_repo_name as repo,
        s.issue_id,
        extract(epoch from d.dtto - pr.created_at) as age,
        lower(pr.dup_user_login) author_login,
        aa.company_name author_company
    from
        pr_sigs s,
        dtto d,
        gha_issues pr
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.user_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
    where s.event_id = pr.event_id
        and pr.dup_repo_name in (select repo_name from trepos)
    ) sub
)
select
  'awaiting_prs_by_sig_repos;' || sub.sig || '`' || sub.repo || ';d7,d10,d30,d60,d90,y' as metric,
  count(distinct sub.issue_id) filter(where sub.age > 604800) as open_7,
  count(distinct sub.issue_id) filter(where sub.age > 864000) as open_10,
  count(distinct sub.issue_id) filter(where sub.age > 2592000) as open_30,
  count(distinct sub.issue_id) filter(where sub.age > 5184000) as open_60,
  count(distinct sub.issue_id) filter(where sub.age > 7776000) as open_90,
  count(distinct sub.issue_id) filter(where sub.age > 31557600) as open_y
from
  prs_with_sig_labels sub
group by
  sub.sig,
  sub.repo
;