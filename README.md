# Redirect Report Repository

This repo contains the script that generates a report of what redirects were
hit from a set of access logs. This report can be emailed out automatically
for triggering in a cron job, see the redirect_report module in the scripts
repo for how this is deployed.

## Testing

This project is specced out, so the standard works:

    bundle exec rspec

There are only functional tests, no unit tests.

## Running

### Synopsis

    redirect_report [log_files...|-]

### Description

The reporting script reads in the redirect files from
`/etc/nginx/conf.d/*redirects.map` and processes any log files provided on the
command-line. `log_file` can be `-` for stdin. Log files will also be
automatically ungzipped if necessary.

The generated report counts how many times each of the redirects listed in the
redirects files was accessed based on these logs provided. The goal is to
understand which redirects are not being used. Several counters are generated
to help classify the accesses and are reported in separate columns:

- `public` - the number of accesses from a public IP that doesn't fall into
  the other categories (below)
- `syndication` - access from the Publify service that syndicates our content
- `google` - accesses from Google's crawler
- `bing` - accesses from Bing's crawler

Accesses that come from smoke tests, of which there are a lot, are not counted
at all.

### Deployment

This report should be run from a cron job on `logging.production.mas` so that
it has access to the log files there. See the `redirect_report` module in our
puppet repo.

### Examples

Running this on `logging.production.mas` would look a little like this:

    redirect_report /var/log/central/nginx/production-frontend.log /var/log/central/nginx/production-frontend.log-2015022[012].gz

    

