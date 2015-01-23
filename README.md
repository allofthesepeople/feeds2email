# feeds2email

Scrape feeds, email list of new articles.

## Setup

List feeds to scrape in `feeds.txt`.

Loads email info from ENV, e.g. add the following to `.profile`:

    export EMAIL_ADDRESS=name@example.com
    export EMAIL_PASSCODE=your-password
    export EMAIL_DOMAIN=example.com
    export EMAIL_SERVER=smtp.example.com


Probably wants to be added to the crontab to run routinely, to run everyday at 8am, run something like:

    00 8 * * * cd ~/feeds2email/ && . $HOME/.profile; ruby scraper.rb >/dev/null


