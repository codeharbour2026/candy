# The Candy Bowl — starter project

A vanilla HTML/CSS/JavaScript school marketplace using Supabase Auth/Postgres and GitHub Pages.

## Current implementation status

This project provides a working starter for the public marketplace, authentication UI, profile display-name editing, listing creation, order placement with stock locking, basic order status actions, reports and a restricted admin overview. It is **not yet approved or certified for real student use**. Review the SQL and security policies with a trusted adult/administrator before launch.

Some advanced features from the project brief are not fully implemented yet, including full strike/appeal administration, notifications UI, listing edit/delete screens, complete order dispute resolution and exhaustive security testing. Do not describe those as finished.

## 1. Create Supabase project
1. Create a project at https://supabase.com/ and wait for provisioning.
2. In Project Settings → API, copy the Project URL and the publishable key (or legacy anon key).
3. Open `supabase.js` and replace `YOUR_SUPABASE_PROJECT_URL` and `YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY`.
4. Never put a service-role/secret key or database password in this file.

## 2. Set up the database
1. Open Supabase → SQL Editor.
2. Open `schema.sql`, copy its contents and run them in a new project.
3. Inspect the output for errors. If a run stops part-way, do not blindly rerun it; resolve the reported issue in a fresh project or make a reviewed migration.
4. Test with two ordinary accounts before trying an admin account.

## 3. Configure authentication redirects
In Supabase → Authentication → URL Configuration:
- Set Site URL to the published GitHub Pages URL, for example `https://YOUR-GITHUB-USERNAME.github.io/YOUR-REPOSITORY/`.
- Add that URL and the relevant page redirects such as `https://YOUR-GITHUB-USERNAME.github.io/YOUR-REPOSITORY/account.html` to Redirect URLs.
- For a repository named `YOUR-GITHUB-USERNAME.github.io`, the site root is `https://YOUR-GITHUB-USERNAME.github.io/`.
- Use the exact URL for your project; do not leave example values in production.

## 4. Deploy to GitHub Pages
1. Create a GitHub repository.
2. Upload the HTML, CSS, JavaScript and SQL documentation files.
3. In repository Settings → Pages, choose deployment from the main branch and root folder.
4. Wait for deployment, then open the published URL.
5. Confirm Supabase's allowed redirect URLs match the deployed site.

## 5. Configure the first administrator
1. Sign up with the intended administrator account and confirm the email if confirmation is enabled.
2. In Supabase → Authentication → Users, find that user and copy the UUID.
3. In SQL Editor, run `update public.profiles set role='admin' where id='PASTE-UUID-HERE';`.
4. Keep admin assignment restricted to a trusted project owner. Never expose the service-role key in browser code.

## 6. Important notes before launch
- School approval is required before student food sales.
- Cash payment is between buyer and seller; no online payments are processed.
- A public listing exposes its product details and seller display name only, not email.
- This is a starter implementation. Review every RLS policy and database function before using real student data.
- In particular, the schema should be security-reviewed before real use; do not treat the presence of RLS as proof that the system is secure.

## 7. Test checklist
- [ ] Public visitors can browse active listings.
- [ ] Search, category, price range and sorting work.
- [ ] Signed-out users are sent to sign in before ordering or listing.
- [ ] Users cannot create listings for another seller.
- [ ] A user cannot order their own listing.
- [ ] Concurrent orders cannot oversell inventory.
- [ ] Orders store a name and unit-price snapshot.
- [ ] Buyers only see their orders; sellers only see orders involving their listings.
- [ ] Cash payment is never automatically marked paid on order creation.
- [ ] Ordinary users cannot change their own role or account status.
- [ ] Reports do not automatically create strikes.
- [ ] Admin-only functions are checked in the database, not just the UI.
- [ ] School policies and food-safety rules are approved before launch.


## Admin suspension controls
For an existing database, run `admin-suspension-migration.sql` in Supabase SQL Editor **after** `schema.sql`. Deploy the updated `script.js` and `styles.css`. Sign in to `admin.html` using an account whose `profiles.role` was securely assigned to `admin`. Under User Management, search for a user, review their history, enter a documented reason and click **Suspend for 30 days**. To reverse it, use **Reinstate user** with a reason. Both actions are checked in PostgreSQL and written to the audit log.

Test using non-production accounts and have a trusted adult review the SQL and school rules before any real student use. Full strike issuance and appeals controls are still not implemented.
