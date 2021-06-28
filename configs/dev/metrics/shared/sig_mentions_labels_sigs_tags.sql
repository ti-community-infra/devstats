select
    -- string_agg(sub2.sig, ',')
    sub2.sig
from (
    select
        sub.sig,
        count(distinct sub.issue_id) as cnt
    from (
        -- 
        select
            sel.sig as sig,
            sel.issue_id
        from (
            select
                distinct issue_id,
                lower(substring(dup_label_name from '(?i)sig/(.*)')) as sig
            from
                gha_issues_labels
            where
                dup_created_at > now() - '2 years'::interval
        ) sel
        where
            sel.sig is not null
    ) sub
    group by
        sub.sig
    having
        count(distinct sub.issue_id) > 10
) sub2
order by
    cnt desc,
    sub2.sig asc
limit {{lim}}
;