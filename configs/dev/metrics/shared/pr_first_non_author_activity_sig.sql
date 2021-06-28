with prs as (
  select
    distinct id,
    pre.dup_repo_name || '#' || pre.number as pr_key,
    dup_repo_id repo_id,
    dup_repo_name repo_name,
    number,
    user_id author_id,
    dup_user_login author_login,
    created_at
  from
    gha_pull_requests pre
  where
    created_at >= '{{from}}'
    and created_at < '{{to}}'
), pr_reponse_events as (
    (
        select
            event_id,
            pr_key,
            updated_at
        from
            gha_issues ie,
            prs pr
        where
            ie.dup_actor_id != pr.author_id
            and ie.dup_repo_name = pr.repo_name
            and ie.number = pr.number
            and ie.created_at >= '{{from}}'
            and ie.created_at < '{{to}}'
            and ie.updated_at > pr.created_at + '30 seconds'::interval
            and ie.dup_type like '%Event'
            -- Ignore the robot's response.
            and (lower(ie.dup_actor_login) {{exclude_bots}})
        order by
            ie.updated_at asc
    )
    union
    (
        select
            event_id,
            pr_key,
            updated_at
        from
            gha_pull_requests pre,
            prs pr
        where
            pre.dup_actor_id != pr.author_id
            and pre.dup_repo_name = pr.repo_name
            and pre.number = pr.number
            and pre.created_at >= '{{from}}'
            and pre.created_at < '{{to}}'
            and pre.updated_at > pr.created_at + '30 seconds'::interval
            and pre.dup_type like '%Event'
            -- Exclude bots.
            and (lower(pre.dup_actor_login) {{exclude_bots}})
        order by
            pre.updated_at asc
    )
), pr_with_last_issue_event as (
    select
        pr_key,
        i.id issue_id,
        last_value(event_id) over issues_ordered_by_update last_issue_event_id
    from
         prs pr,
         gha_issues i
    where
         pr.repo_name = i.dup_repo_name
         and pr.repo_id = i.dup_repo_id
         and pr.number = i.number
    window
        issues_ordered_by_update as (
            partition by pr.pr_key
            order by
                updated_at asc,
                event_id asc
            range between current row
            and unbounded following
        )
), pr_sig_labels as (
    select
        pr_key,
        sig
    from
    (
        select
            distinct pr_key,
            lower(substring(il.dup_label_name from '(?i)sig/(.*)')) as sig
        from
            gha_issues_labels il,
            pr_with_last_issue_event i
        where
            il.event_id = i.last_issue_event_id
    ) sub
    where
        sig is not null
        and sig in (select sig_mentions_labels_name from tsig_mentions_labels)
),  pr_tdiff as (
    select
        pr.pr_key,
        repo_name,
        number,
        r.repo_group,
        coalesce(l.sig, 'non-category') as sig,
        -- So far, PingCAP is the company with the largest contribution to the TiDB community,
        -- but other companies may still become the company with the largest contribution.
        case when aa.company_name = 'PingCAP' then 'top-contrib'
             when lower(pr.author_login) like any(array[
                'dependabot', 'ti-srebot', 'codecov-io', 'web-flow',  'prowbot', 'travis%bot', 'k8s-%', '%-bot',
                '%-robot', 'bot-%', 'robot-%', '%[bot]%', '%[robot]%', '%-jenkins', 'jenkins-%', '%-ci%bot',
                '%-testing', 'codecov-%', '%clabot%', '%cla-bot%', '%-gerrit', '%-bot-%', '%cibot', '%-ci'
             ]) then 'only-bots'
             else 'other-company'
        end as author_type,
        extract(epoch from sub.first_response_at - pr.created_at) / 3600 as diff
    from
        prs pr
    left join
        -- Get the first response time for each PR.
        (
            select
                distinct on(prre.pr_key) pr_key,
                first_value(updated_at) over events_ordered_by_update as first_response_at
            from
                pr_reponse_events prre
            window
                events_ordered_by_update as (
                    partition by pr_key
                    order by
                        updated_at asc,
                        event_id asc
                    range between current row
                    and unbounded following
                )
        ) sub
    on
        pr.pr_key = sub.pr_key
    -- Notice: A PR belongs to only one repo group.
    left join
        gha_repos r
    on
        repo_id = r.id
        and repo_name = r.name
    -- Notice: The author of the PR may belong to multiple companies at the same time.
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.author_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
    -- Notice: A PR may belong to multiple SIGs.
    left join
        pr_sig_labels l
    on
        pr.pr_key = l.pr_key
)
-- All repositories and all author type and all SIG.
select
    'non_auth_sig;All_All_All;p15,med,p85' as name,
    percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
    percentile_disc(0.5) within group (order by diff asc) as non_author_median,
    percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
from
    (
        select
            distinct on (pr_key)
            diff
        from
            pr_tdiff
    ) sub
-- All repositories and author type group and all SIG.
union
(
	select
		'non_auth_sig;All_' || author_type || '_All;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as non_author_median,
        percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
	from
		(
            select
                distinct on (pr_key || author_type)
                author_type,
                diff
            from
                pr_tdiff
        ) sub
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
        percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as non_author_median,
        percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
	from
		(
            select
                distinct on (pr_key || repo_group)
                repo_group,
                diff
            from
                pr_tdiff
        ) sub
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
        percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as non_author_median,
        percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
	from
		(
            select
                distinct on (pr_key || repo_group)
                author_type,
                repo_group,
                diff
            from
                pr_tdiff
        ) sub
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
        percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as non_author_median,
        percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
    from
        (
            select
                distinct on (pr_key || sig)
                sig,
                diff
            from
                pr_tdiff
        ) sub
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
        percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as non_author_median,
        percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
	from
		(
            select
                distinct on (pr_key || author_type || sig)
                author_type,
                sig,
                diff
            from
                pr_tdiff
        ) sub
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
        percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as non_author_median,
        percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
	from
	     (
            select
                distinct on (pr_key || repo_group)
                repo_group,
                sig,
                diff
            from
                pr_tdiff
        ) subpr_tdiff
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
        percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as non_author_median,
        percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
	from
		(
            select
                distinct on (pr_key || repo_group || author_type || sig)
                repo_group,
                author_type,
                sig,
                diff
            from
                pr_tdiff
        ) sub
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