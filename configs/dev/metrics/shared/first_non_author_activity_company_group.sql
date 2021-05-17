with issues as (
  -- PR releted issue with author.
  select distinct id,
    user_id,
    created_at
  from
    gha_issues
  where
    is_pull_request = true
    and created_at >= '{{from}}'
    and created_at < '{{to}}'
    and (lower(dup_user_login) {{exclude_bots}})
), prs as (
  -- PR with author.
  select distinct id,
    user_id,
    created_at
  from
    gha_pull_requests
  where
    created_at >= '{{from}}'
    and created_at < '{{to}}'
    and (lower(dup_user_login) {{exclude_bots}})
), tdiffs as (
  -- Compute the time difference between PR open to first non-author engagement according to related issue.
  select
    extract(epoch from i2.updated_at - i.created_at) / 3600 as diff,
    r.repo_group as repo_group,
    aa.company_name as company
  from
    issues i,
    gha_repos r,
    gha_actors_affiliations aa,
    gha_issues i2
  where
    i.id = i2.id
    and r.name = i2.dup_repo_name
    and r.id = i2.dup_repo_id
    and i2.created_at >= '{{from}}'
    and i2.created_at < '{{to}}'
    -- Exclude bots.
    and (lower(i2.dup_actor_login) {{exclude_bots}})
    -- Select the company of pr author.
    and aa.actor_id = i.user_id
    and aa.company_name in (select companies_name from tcompanies)
    -- Select the activity event triggered by the first non author of PR.
    and i2.event_id in (
      select event_id
      from
        gha_issues sub
      where
        sub.dup_actor_id != i.user_id
        and sub.id = i.id
        and sub.created_at >= '{{from}}'
        and sub.created_at < '{{to}}'
        and sub.updated_at > i.created_at + '30 seconds'::interval
        and sub.dup_type like '%Event'
      order by
        sub.updated_at asc
      limit 1
    )
  union
  -- Compute the time difference between PR open to first non-author engagement according to PR.
  select 
    extract(epoch from p2.updated_at - p.created_at) / 3600 as diff,
    r.repo_group as repo_group,
    aa.company_name as company
  from
    prs p,
    gha_repos r,
    gha_actors_affiliations aa,
    gha_pull_requests p2
  where
    p.id = p2.id
    and r.name = p2.dup_repo_name
    and r.id = p2.dup_repo_id
    and p2.created_at >= '{{from}}'
    and p2.created_at < '{{to}}'
    -- Exclude bots.
    and (lower(p2.dup_actor_login) {{exclude_bots}})
    -- Select the company of pr author.
    and aa.actor_id = p.user_id
    and aa.company_name in (select companies_name from tcompanies)
    -- Select the activity event triggered by the first non author of PR.
    and p2.event_id in (
      select event_id
      from
        gha_pull_requests sub
      where
        sub.dup_actor_id != p.user_id        -- Non author
        and sub.id = p.id
        and sub.created_at >= '{{from}}'
        and sub.created_at < '{{to}}'
        and sub.updated_at > p.created_at + '30 seconds'::interval
        and sub.dup_type like '%Event'
      order by
        sub.updated_at asc
      limit 1
    )
)
-- All repository and all company.
select
  'non_auth_company;All_All;p15,med,p85' as name,
  percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
  percentile_disc(0.5) within group (order by diff asc) as non_author_median,
  percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
from
  tdiffs
-- Repository group and all company.
union
(
	select
		'non_auth_company;' || repo_group || '_All;p15,med,p85' as name,
		percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
		percentile_disc(0.5) within group (order by diff asc) as non_author_median,
		percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
	from
		tdiffs
	where
		repo_group is not null
	group by
		repo_group
	order by
		non_author_median desc,
		name asc
)
-- All repository and company group.
union
(
	select 
		'non_auth_company;All_' || company || ';p15,med,p85' as name,
		percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
		percentile_disc(0.5) within group (order by diff asc) as non_author_median,
		percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
	from
		tdiffs
	where
		company is not null
	group by
		company
	order by
		non_author_median desc,
		name asc
)
-- Repository group and company group.
union
(
	select 
		'non_auth_company;' || repo_group || '_' || company || ';p15,med,p85' as name,
		percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
		percentile_disc(0.5) within group (order by diff asc) as non_author_median,
		percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
	from
		tdiffs
	where
		repo_group is not null
		and company is not null
	group by
		repo_group,
		company
	order by
		non_author_median desc,
		name asc
)
;