with issues as (
    -- PR related issue with author and last event id.
    select
        distinct id,
        last_value(event_id) over issues_ordered_by_update as last_event_id,
        dup_repo_name repo_name,
        number,
        user_id,
        dup_user_login user_login,
        created_at
    from
        gha_issues
    where
        is_pull_request = true
        and created_at >= '{{from}}'
        and created_at < '{{to}}'
        and (lower(dup_user_login) {{exclude_bots}})
    window
      issues_ordered_by_update as (
        partition by id
        order by
          updated_at asc,
          event_id asc
        range between current row
        and unbounded following
      )
), prs as (
    -- PR with author and last event id.
    select
        distinct id,
        last_value(event_id) over prs_ordered_by_update as last_event_id,
        dup_repo_name repo_name,
        number,
        user_id,
        dup_user_login user_login,
        created_at
    from
        gha_pull_requests
    where
        created_at >= '{{from}}'
        and created_at < '{{to}}'
        and (lower(dup_user_login) {{exclude_bots}})
    window prs_ordered_by_update as (
        partition by id
        order by
          updated_at asc,
          event_id asc
        range between current row
        and unbounded following
    )
), issues_sigs_label as (
    select
      sub.id,
      sub.sig
    from (
      select
        i.id,
        lower(substring(il.dup_label_name from '(?i)sig/(.*)')) as sig
      from
        gha_issues_labels il,
        issues i
      where
        il.dup_repo_name = i.repo_name
        and il.dup_issue_number = i.number
      ) sub
    where
      sub.sig is not null
      and sub.sig in (select sig_mentions_labels_name from tsig_mentions_labels)
), prs_sigs_label as (
    select
      sub.id,
      sub.sig
    from (
      select
        p.id,
        lower(substring(il.dup_label_name from '(?i)sig/(.*)')) as sig
      from
        gha_issues_labels il,
        prs p
      where
        il.dup_repo_name = p.repo_name
        and il.dup_issue_number = p.number
      ) sub
    where
      sub.sig is not null
      and sub.sig in (select sig_mentions_labels_name from tsig_mentions_labels)
), tdiffs_with_sigs as (
    -- Compute the time diff between PR open to first non-author engagement according to related issue.
    select
        i.number,
        extract(epoch from i2.updated_at - i.created_at) / 3600 as diff,
        r.repo_group as repo_group,
        case when aa.company_name = 'PingCAP' then 'is-top-contributing-company'
             when lower(i.user_login) like any(array[
                'dependabot', 'ti-srebot', 'codecov-io', 'web-flow',  'prowbot', 'travis%bot', 'k8s-%', '%-bot',
                '%-robot', 'bot-%', 'robot-%', '%[bot]%', '%[robot]%', '%-jenkins', 'jenkins-%', '%-ci%bot',
                '%-testing', 'codecov-%', '%clabot%', '%cla-bot%', '%-gerrit', '%-bot-%', '%cibot', '%-ci'
             ]) then 'only-bots'
             else 'not-top-contributing-company'
        end as author_type,
        isl.sig
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
    left join
        issues_sigs_label isl
    on
        i.id = isl.id
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
        p.number,
        extract(epoch from p2.updated_at - p.created_at) / 3600 as diff,
        r.repo_group as repo_group,
        case when aa.company_name = 'PingCAP' then 'is-top-contributing-company'
             when lower(p.user_login) like any(array[
                'dependabot', 'ti-srebot', 'codecov-io', 'web-flow',  'prowbot', 'travis%bot', 'k8s-%', '%-bot',
                '%-robot', 'bot-%', 'robot-%', '%[bot]%', '%[robot]%', '%-jenkins', 'jenkins-%', '%-ci%bot',
                '%-testing', 'codecov-%', '%clabot%', '%cla-bot%', '%-gerrit', '%-bot-%', '%cibot', '%-ci'
             ]) then 'only-bots'
             else 'not-top-contributing-company'
        end as author_type,
        psl.sig
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
    left join
        prs_sigs_label psl
    on
        p.id = psl.id
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
-- All repositories and all author type and all SIG.
select
    'non_auth_sig;All_All_All;p15,med,p85' as name,
    greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
    greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
    greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
from
    tdiffs_with_sigs
-- All repositories and author type group and all SIG.
union
(
	select
		'non_auth_sig;All_' || author_type || '_All;p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs_with_sigs
	group by
	    author_type
	order by
		non_author_median desc,
		name asc
)
-- Repository groups and all author type and all SIG.
union
(
	select
		'non_auth_sig;' || repo_group || '_All_All;p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs_with_sigs
	where
		repo_group is not null
	group by
		repo_group
	order by
		non_author_median desc,
		name asc
)
-- Repository groups and author type group and all SIG.
union
(
	select
		'non_auth_sig;' || repo_group || '_' || author_type || '_All;p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs_with_sigs
	where
		repo_group is not null
	    and author_type is not null
	group by
		repo_group,
        author_type
	order by
		non_author_median desc,
		name asc
)

-- All repositories and all author type and SIG group.
union
(
    select
        'non_auth_sig;All_All_' || sig || ';p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
    from
        tdiffs_with_sigs
    where
        sig is not null
    group by
        sig
)
-- All repositories and author type group and SIG group.
union
(
	select
		'non_auth_sig;All_' || author_type || '_' || sig || ';p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs_with_sigs
	where
	    author_type is not null
	    and sig is not null
	group by
	    author_type,
        sig
	order by
		non_author_median desc,
		name asc
)
-- Repository groups and all author type and SIG group.
union
(
	select
		'non_auth_sig;' || repo_group || '_All_' || sig || ';p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs_with_sigs
	where
		repo_group is not null
	    and sig is not null
	group by
		repo_group,
        sig
	order by
		non_author_median desc,
		name asc
)
-- Repository groups and author type group and SIG group.
union
(
	select
		'non_auth_sig;' || repo_group || '_' || author_type ||  '_' || sig || ';p15,med,p85' as name,
        greatest(percentile_disc(0.15) within group (order by diff asc), 0) as non_author_15_percentile,
        greatest(percentile_disc(0.5) within group (order by diff asc), 0) as non_author_median,
        greatest(percentile_disc(0.85) within group (order by diff asc), 0) as non_author_85_percentile
	from
		tdiffs_with_sigs
	where
		repo_group is not null
	    and author_type is not null
	    and sig is not null
	group by
		repo_group,
        author_type,
        sig
	order by
		non_author_median desc,
		name asc
)
;