select
  'sigm_txt,' || sub2.sig as sig,
  round(count(distinct sub2.eid) / {{n}}, 2) as count_value
from (
  select case sub.sig
      when 'aws' then 'cloud-provider'
      when 'azure' then 'cloud-provider'
      when 'batchd' then 'cloud-provider'
      when 'cloud-provider-aws' then 'cloud-provider'
      when 'gcp' then 'cloud-provider'
      when 'ibmcloud' then 'cloud-provider'
      when 'openstack' then 'cloud-provider'
      when 'vmware' then 'cloud-provider'
      else sub.sig
    end as sig,
    sub.eid
  from (
    select substring(sel.sig from 17) as sig,
      sel.eid
    from
      (
        select event_id as eid,
          lower(coalesce(
            substring(
              body from '(?i)(?:^|\s)+(@kubernetes/sig-[\w\d-]+)(?:-bug|-feature-request|-pr-review|-api-review|-misc|-proposal|-design-proposal|-testlib-failure|-owners)s?(?:$|[^\w\d-]+)'
            ),
            substring(
              body from '(?i)(?:^|\s)+(@kubernetes/sig-[\w\d-]*[\w\d]+)(?:$|[^\w\d-]+)'
            )
          )) as sig
        from
          gha_texts
        where
          (lower(actor_login) {{exclude_bots}})
          and created_at >= '{{from}}'
          and created_at < '{{to}}'
      ) sel
    where
      sel.sig is not null
      and sel.sig not in (
        'apimachinery', 'api-machiner', 'cloude-provider', 'nework',
        'scalability-proprosals', 'storge', 'ui-preview-reviewes',
        'cluster-fifecycle', 'rktnetes'
      )
      and sel.sig not like '%use-only-as-a-last-resort'
  ) sub
) sub2
where
  sub2.sig in (select sig_mentions_texts_name from tsig_mentions_texts)
group by
  sub2.sig
order by
  count_value desc,
  sub2.sig asc
;
