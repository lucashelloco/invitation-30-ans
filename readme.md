# RSVP — les 30 ans

```
index.html          page invités (le lien à envoyer)
admin/index.html    tableau de bord organisateurs → https://ton-site/admin
config.js           URL + clé publique Supabase (partagé par les 2 pages)
supabase/schema.sql tables, sécurité RLS, fonction d'envoi
_redirects          (Netlify) fait pointer /admin vers admin/index.html
_headers            (Netlify) en-têtes de sécurité : CSP, anti-iframe, HSTS…
```

## 1. Supabase
1. Crée un projet sur supabase.com (région Europe).
2. **SQL Editor** → colle `supabase/schema.sql`, remplace les 4 e-mails à la fin, puis **Run**.
3. **Authentication → Users → Add user → Create new user** : crée les 4 comptes (e-mail + mot de passe, coche *Auto Confirm User*).
4. **Authentication → Sign In / Providers** : désactive *Allow new users to sign up*. Plus personne d'autre ne pourra créer de compte.
5. **Project Settings → API** : copie l'URL du projet et la clé *anon* (ou *publishable*) dans `config.js`.

> Pour ajouter ou retirer un organisateur plus tard : modifie la table `admins` (Table Editor) et le compte dans Authentication.

## 2. Mise en ligne (Netlify)
- Glisse le dossier entier sur https://app.netlify.com/drop (crée un compte gratuit pour que le site reste en ligne).
- Dans *Site configuration*, renomme le site (ex. `30ans-cerisy.netlify.app`).
- Page invités : `https://30ans-cerisy.netlify.app` — admin : `https://30ans-cerisy.netlify.app/admin`

GitHub Pages fonctionne aussi (`/admin/` avec la barre finale).

## 3. Avant d'envoyer le lien
- Remplis le bloc `CONFIG` en haut de `index.html` (date, prénoms, adresse, horaires, date limite).
- Fais une réponse test, vérifie qu'elle apparaît dans /admin, puis supprime-la.

## Sécurité, en bref
- Les invités n'ont accès qu'à la fonction `submit_rsvp` : ils ne peuvent ni lire ni supprimer les réponses des autres.
- Seuls les comptes connectés dont l'e-mail est dans `admins` lisent et suppriment.
- La clé dans `config.js` est publique par conception ; ne mets jamais la clé `service_role`.
- Supabase met en pause les projets gratuits après 7 jours sans activité : passe sur le dashboard de temps en temps entre l'envoi et la fête si les réponses se font rares.
