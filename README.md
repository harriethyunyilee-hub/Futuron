# FUTURON — Full-stack web MVP

Mobile-first web app based on the supplied 16-screen Futuron design reference. This is original implementation code, **not** an export or copy of Claude's original source.

## What's implemented

- Sign up / sign in / sign out using Supabase Auth (email and password)
- User profile and favorite sport (Supabase Postgres)
- One-time 2,500 **virtual, non-redeemable** points for each account
- Balance and transaction history stored per user
- Fictional example matches, picks, prediction submission and activity history
- Transactionally safe server-side point deduction via a PostgreSQL RPC, with a unique constraint against double picks
- Row Level Security policies isolating each user's private information
- Mobile-first, dark brown and cream Futuron-style UI; onboarding, home, picks, wallet, profile, match details
- GitHub → Vercel continuous deployment ready

## Not implemented yet

Real sports data, AI match simulations, settlement, payouts, payment processing, deposits, real-money wagering, user-to-user transfers, admin dashboard and redemptions. **There is no real-money or cash-equivalent functionality.** The HTML export of Claude may contain other behaviors not represented here.

## 1. Create the database

1. Go to https://supabase.com/dashboard and create a new project.
2. Open **SQL Editor** → **New query**. Copy and execute all of `supabase/schema.sql` **once**. Do this before inviting users. The trigger gives each newly created account 2,500 demo points.
3. Under **Authentication → Providers → Email**, keep Email enabled; decide whether **Confirm email** should remain enabled (recommended).
4. Under **Authentication → URL Configuration**, set Site URL to your actual Vercel domain and add both development (`http://localhost:5173/**`) and deployment redirect URLs (`https://YOUR_APP.vercel.app/**` and your custom domain if used).

## 2. Local development

Requires Node.js 20+ and npm.

```bash
npm install
cp .env.example .env.local
```

Fill `.env.local` with values from **Supabase → Project Settings → API** / project **Connect** dialog:

```
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

The publishable key (or legacy anon key) is safe in the client **when RLS is correctly configured**. **Never** expose the secret / service_role key in client code or Vercel `VITE_` variables.

```bash
npm run dev
```

## 3. Deploy on GitHub + Vercel

1. Push the entire folder contents (including `src`, `supabase`, `package.json`, `index.html` and `vercel.json`) to a **new repo**, or replace the old single-HTML prototype in your existing Futuron repo after backing it up. Do **not** upload `node_modules`, `dist` or `.env.local`.
2. In Vercel, import your repo. Framework preset should be **Vite** (auto-detected). If necessary set **Build Command** to `npm run build` and **Output Directory** to `dist`.
3. In **Project → Settings → Environment Variables**, set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` using your project's values; apply to Production (and Preview if needed).
4. Deploy or redeploy; test registration, email confirmation, login, profile, wallet, and placing a prediction.
5. To connect a custom domain, use **Project → Settings → Domains** and follow Vercel's exact DNS instructions at your domain registrar (including Wix if your domain is held there).

## Architecture/security notes

- Clients can SELECT their own data but cannot directly INSERT or UPDATE wallets, predictions or transaction records.
- `place_prediction` executes on Postgres, requires `auth.uid()`, locks the wallet row, enforces allowed stakes, checks upcoming fixtures, records one pick per match and debits points atomically.
- `point_transactions` is an append-only ledger from the user's perspective.
- No endpoint exists to add arbitrary points or settle games from the browser.
- Production systems need database tests, rate limits, abuse controls, monitoring and an audited, server-only settlement process.
- The demo fixtures are fictional and use future dates relative to when the SQL is executed. There is no automatic live sports feed.
- A new Supabase project is required; this app is **not connected** to any account until you complete setup.
- Vercel Hobby is intended for non-commercial personal use; review pricing/terms before commercial launch.

## Testing checklist

- [ ] Can sign up, verify email and log in
- [ ] New wallet starts at 2,500 virtual points
- [ ] Submitting a 100-point pick yields 2,400 points and a ledger entry
- [ ] Submitting a second pick on the same match is blocked
- [ ] Insufficient points are rejected by the database, even if a browser client is modified
- [ ] Another signed-in user cannot see the first account's wallet, ledger or predictions
- [ ] Direct refresh of site routes works on Vercel
- [ ] Mobile layout and accessible button labels work

## Note on live matches and rewards

This first version supports *prediction tracking only*. It does not settle wins automatically or credit winnings because verified event results and a trusted settlement backend have not been integrated. All points are play-only, not redeemable, non-transferable and have no cash value.
