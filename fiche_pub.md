# Homeless Tycoon — fiche pub

**Site :** [homelesstycoon.vercel.app](https://homelesstycoon.vercel.app) (jamais un portail)
**Couleurs :** `#FFD23F` jaune (« HOMELESS »), `#7EE08A` vert (« TYCOON »), `#2A1F3D` violet encre (contours et textes), `#5EC8FF` bleu ciel (rayons du logo), `#EF476F` rose rouge (accents)
**Langue du public :** anglais (version CrazyGames, anglais par défaut) / français (version du site, français par défaut)
**Logo :** `logo/logo.png` (avec le slogan français « Des poubelles à l'empire »), `logo/logo-sans-slogan.svg` (titre seul, pour un public anglais), `logo/avatar.png` (carré, titre seul)

## Le jeu en une phrase

Tu pars d'une poubelle à Paris et tu bâtis un empire à travers 4 villes, jusqu'à devenir le Roi du Drift à Tokyo.

## Le geste de base

Marcher sur les déchets pour les ramasser, puis vider son sac dans une poubelle verte pour être payé.

## Ce qui impressionne le plus (du plus fort au moins fort)

1. La course de drift en 3D au pied du Mont Fuji : nitro, « SUPER MINI-TURBO », dépassement du Roi du Drift, puis « VICTORY! » et feu d'artifice.
2. Les 4 villes, chacune avec son ambiance : Paris en journée, Londres sous la pluie, New York de nuit, Tokyo de nuit avec lanternes, néons et distributeurs lumineux.
3. Les véhicules et leur customisation : à pied → skate → trottinette → scooter, puis chopper, motocross ou sportive, avec peinture, flammes, néons, jantes dorées. La motocross et la sportive se cabrent au démarrage, le chopper crache de la fumée.
4. La rue qui se remplit : au début des façades « À VENDRE » et 12 €, puis des distributeurs partout, des boutiques rachetées (« YOURS »), des employés qui ramassent, et le compteur d'argent qui s'envole.
5. La Pigeon Tower de New York, qui monte étage par étage jusqu'à 50.
6. Le casino : blackjack naturel, roulette avec la case dorée ×5, et des tables partagées à plusieurs joueurs.
7. Le Pigeon Légendaire : on l'attrape, pluie de pièces et frénésie dorée ×3.
8. Le casse de Wall Street : piratage, perceuse sur le coffre, fuite en voiture entre les taxis.
9. Le personnage : tenue de départ (casquette, t-shirt) → costume trois-pièces et haut-de-forme.

## Avant / après à filmer

* La rue de Paris au début (façades à vendre, 12 €, aucun revenu) vs la même rue rachetée (distributeurs, boutiques, employés, « +17,5 k€ » qui volent).
* Le personnage à pied en tenue de départ vs en costume et haut-de-forme sur la sportive à flammes et néon bleu.
* La Pigeon Tower au chantier (étage 0) vs la tour de 50 étages.
* L'argent : 12 € à Paris vs plusieurs milliards de yens à Tokyo.
* Le scooter de base (Vespa vert) vs le même véhicule après le garage tuning.

## Commandes de démo (si le jeu en a)

Le jeu n'en a pas pour l'instant : il n'y a ni `?demo=1`, ni `window.__adCtl`.

Les vidéos existantes ont été tournées avec un outil interne qui pilote une copie de test du jeu. Je peux ajouter de vraies commandes de démo sur ce modèle : argent, niveau des boutiques, ville, tenue, véhicule, arme, et liste des choix. En mode démo, le score et la sauvegarde en ligne seraient coupés, pour ne pas fausser le classement.

## Sauvegardes de démo (optionnel)

Aucune pour l'instant. La partie est enregistrée dans le navigateur (clé `poubelle-tycoon-v1`). Des sauvegardes « début », « milieu » et « fin » peuvent être créées en même temps que les commandes de démo.

## À ne jamais montrer

* Les vrais pseudos du classement et des visites (MoussMouss, Nonow…) : ce sont de vrais joueurs. Utiliser des pseudos inventés.
* L'écran de connexion (pseudo + mot de passe) et la fenêtre « Mon compte ».
* L'espace pub factice de 30 s de la version du site (« Espace publicitaire »).
* Les messages techniques : « Base Supabase pas à jour… », « présence indisponible », « hors ligne ».
* Un mélange de langues : tout en anglais ou tout en français dans une même pub. Le logo avec slogan est en français.
* Les fenêtres qui couvrent le jeu sans rien montrer : récompense de connexion, cartes du tutoriel, « Mission complete! ».
* Les armes et les braquages de passants ou de joueurs : à vérifier selon la régie, certaines refusent la violence ou le vol dans les pubs.

## Idées ou envies pour les pubs

* « From trash… to empire! » : du ramassage de canettes à la victoire au Mont Fuji, en coupes rapides. C'est la vidéo de preview actuelle (`crazygames/assets/`).
* Un défilé des véhicules façon « choisis ta monture » : skate, trottinette, Vespa, chopper, motocross, sportive, chacun avec sa peinture et ses stickers.
* Un avant / après de la rue en écran partagé : niveau 1 à gauche, rue rachetée à droite.
* La course de drift seule, en accroche des 2 premières secondes.
* Les moments satisfaisants : compteur d'argent qui s'envole, pluie de pièces du Pigeon Légendaire, blackjack naturel.
* « Visite la rue de ton pote » : deux persos côte à côte, puis la roulette à deux.
* Le tour du monde : la carte avec Paris → Londres → New York → Tokyo qui se débloquent.

**Assets existants :**
* Covers : `crazygames/assets/cover_*`
* Vidéos : `homeless-tycoon-preview-20s.mp4` (paysage), `homeless-tycoon-preview-portrait-2x3.mp4` (portrait 2:3), `homeless-tycoon-preview-vertical.mp4` (9:16), dans `crazygames/assets/`
