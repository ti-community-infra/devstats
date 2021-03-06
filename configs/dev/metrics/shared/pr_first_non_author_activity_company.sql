with issues as (
    -- PR related issue with author.
    select
        distinct id,
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
    select
        distinct id,
        user_id,
        created_at
    from
        gha_pull_requests
    where
        created_at >= '{{from}}'
        and created_at < '{{to}}'
        and (lower(dup_user_login) {{exclude_bots}})
), tdiffs as (
    -- Compute the time diff between PR open to first non-author engagement according to related issue.
    select
        extract(epoch from i2.updated_at - i.created_at) / 3600 as diff,
        r.repo_group as repo_group,
        CASE WHEN aa.company_name = 'PingCAP' THEN 'is-top-contributing-company'
             ELSE 'not-top-contributing-company'
        END company_category
    from
        gha_repos r,
        gha_issues i2,
        issues i
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = i.user_id
        and aa.dt_from <= i.created_at
        and aa.dt_to > i.created_at
    where
        i.id = i2.id
        and r.name = i2.dup_repo_name
        and r.id = i2.dup_repo_id
        and i2.created_at >= '{{from}}'
        and i2.created_at < '{{to}}'
        -- Exclude bots.
        and (lower(i2.dup_actor_login) {{exclude_bots}})
        -- Select the first activity event triggered by the non-author.
        and i2.event_id in (
            select
                event_id
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
    -- Compute the time diff between PR open to first non-author engagement according to PR.
    select
        extract(epoch from p2.updated_at - p.created_at) / 3600 as diff,
        r.repo_group as repo_group,
        CASE WHEN aa.company_name = 'PingCAP' THEN 'is-top-contributing-company'
             ELSE 'not-top-contributing-company'
        END company_category
    from
        gha_repos r,
        gha_pull_requests p2,
        prs p
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = p.user_id
        and aa.dt_from <= p.created_at
        and aa.dt_to > p.created_at
    where
        p.id = p2.id
        and r.name = p2.dup_repo_name
        and r.id = p2.dup_repo_id
        and p2.created_at >= '{{from}}'
        and p2.created_at < '{{to}}'
        -- Exclude bots.
        and (lower(p2.dup_actor_login) {{exclude_bots}})
        -- Select the first activity event triggered by the non-author.
        and p2.event_id in (
            select
               event_id
            from
                gha_pull_requests sub
            where
                sub.dup_actor_id != p.user_id
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
-- All repositories and all contributors.
select
    'non_auth_company;All_All;p15,med,p85' as name,
    greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
    greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
    greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
from
    tdiffs
-- All repositories and not-top-contributing-company contributors.
union
(
	select
		'non_auth_company;All_not-top-contributing-company;p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs
	where
		company_category = 'not-top-contributing-company'
	order by
		non_author_median desc,
		name asc
)
-- All repositories and is-top-contributing-company contributors.
union
(
	select
		'non_auth_company;All_is-top-contributing-company;p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs
	where
		company_category = 'is-top-contributing-company'
	order by
		non_author_median desc,
		name asc
)
-- Repository groups and all contributors.
union
(
	select
		'non_auth_company;' || repo_group || '_All;p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
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
-- Repository groups and is-top-contributing-company contributors.
union
(
	select
		'non_auth_company;' || repo_group || '_is-top-contributing-company;p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs
	where
		repo_group is not null
	    and company_category = 'is-top-contributing-company'
	group by
		repo_group
	order by
		non_author_median desc,
		name asc
)
-- Repository groups and not-top-contributing-company contributors.
union
(
	select
		'non_auth_company;' || repo_group || '_not-top-contributing-company;p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs
	where
		repo_group is not null
        and company_category = 'not-top-contributing-company'
	group by
		repo_group
	order by
		non_author_median desc,
		name asc
)
;