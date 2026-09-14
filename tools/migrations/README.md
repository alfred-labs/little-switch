# Migrer les anciennes tâches Codex vers `openai`

Après le passage à LittleSwitch 0.5.0, Codex peut afficher
`Model provider ... not found` à la reprise d'une ancienne tâche.
La configuration utilise désormais le fournisseur natif `openai`, mais
l'identifiant précédent reste dans la base SQLite et les fichiers de session.

[migrate-codex-provider.sh](migrate-codex-provider.sh) migre **tous les identifiants
de fournisseur vers `openai`** : `little-switch`, les anciens `alfred-profile-*`
et les autres fournisseurs enregistrés. Les tâches utilisant déjà `openai`
restent inchangées. Les modèles, titres, instructions et messages sont conservés.
Le script ne modifie ni la configuration ni l'authentification.

## Utilisation

Prérequis : Bash, Python **3.11 ou plus récent**, et `lsof` (fourni par macOS).
Le script recherche un Python compatible dans le `PATH`, dont `python3.11` à
`python3.14`, sans installer de dépendances.

Appliquer d'abord l'intégration Codex dans LittleSwitch 0.5.0 ou une version
ultérieure. Le script vérifie que le fournisseur natif est actif et que
`openai_base_url` pointe vers `http://127.0.0.1:11436/v1`.

Depuis la racine du dépôt, lancer la simulation :

```bash
bash tools/migrations/migrate-codex-provider.sh --dry-run
```

L'absence d'option équivaut à `--dry-run`. La simulation affiche des compteurs
sans modifier les fichiers Codex. Elle lit SQLite depuis des copies temporaires
privées, supprimées à la fin, pour ne pas créer de fichiers WAL dans le profil.
`CODEX_HOME` est respecté ; pour un autre répertoire, ajouter
`--codex-home "/chemin/vers/.codex"` aux commandes.

Pour appliquer, **quitter Codex et les sessions Codex CLI**, puis exécuter depuis
Terminal :

```bash
bash tools/migrations/migrate-codex-provider.sh --apply
```

Le script refuse d'écrire si un autre processus utilise les fichiers concernés.
Il ne ferme et ne relance aucune application. LittleSwitch peut rester ouvert.
Après `Migration verified`, rouvrir Codex puis une ancienne tâche.

## Sauvegarde et récupération

Avant modification, les bases SQLite (y compris les transactions WAL validées)
et les sessions concernées sont sauvegardées dans un nouveau répertoire privé :

```text
$CODEX_HOME/little-switch-provider-backups/migration-*/
```

Le chemin exact est affiché et `manifest.json` inventorie les fichiers.
Ces sauvegardes contiennent l'historique des tâches : les conserver privées.

Une erreur pendant l'application provoque un retour arrière. Si celui-ci échoue,
le script l'annonce : garder Codex fermé et conserver la sauvegarde. Une
interruption brutale peut laisser une migration partielle ; relancer le script
termine les références restantes. Après succès, une nouvelle exécution ne crée
pas de nouvelle sauvegarde.

Pour une restauration manuelle immédiate, garder Codex fermé. Restaurer les bases
avec l'API de sauvegarde SQLite ou sa commande `.restore`, puis remettre les
sessions du manifeste à leurs chemins relatifs d'origine. Une restauration après
reprise du travail remplacerait les nouvelles données : sauvegarder aussi l'état
courant avant une telle récupération.

## Limites et validation

Le script traite les fichiers `.jsonl` actifs et archivés, y compris non indexés,
et les bases `state_N.sqlite` du répertoire Codex. Il refuse les sessions
compressées `.jsonl.zst`, un répertoire SQLite séparé et les schémas inconnus.
Les en-têtes vides ou non reconnus sans référence depuis une tâche à migrer sont
comptés et ignorés. Un fichier manquant ou incohérent référencé par une tâche à
migrer bloque l'opération avant toute modification.
Un dossier de sessions illisible ou une configuration modifiée pendant
l'inspection bloque également l'opération.

Le script migre les références de fournisseur ; il ne met pas à jour le binaire
LittleSwitch. Un modèle historique qui n'est plus exposé par LittleSwitch devra
être remplacé dans Codex. La validation finale consiste à reprendre une ancienne
tâche avec LittleSwitch actif.

Les tests utilisent exclusivement des données synthétiques :

```bash
mise run tools:test -- --filter CodexProviderMigration
```
