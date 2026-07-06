# The Styk
Des notes virtuelles qui vivent dans les dossiers de votre Mac.

The Styk est un tout petit programme qui maintient des notes numériques ancrées à vos dossiers du Finder. Une note flotte sur l'écran pendant que vous êtes dans le dossier où vous l'avez créée -- quittez le dossier, elle disparaît ; revenez, elle réapparaît.

## Installation

Téléchargez The Styk sur https://setor101.com.br/apps et glissez-le dans votre dossier Applications, puis double-cliquez sur l'icône pour le lancer.

## Utilisation

The Styk place une icône de note sur le côté droit de votre barre de menus. Cliquez sur l'icône pour afficher le menu. De là, vous pouvez choisir **"Nouvelle note dans ce dossier"** pour créer une note. Écrivez dedans ; la note s'enregistre automatiquement.

### Barre de menus
Le menu de la barre d'état répertorie toutes les notes, regroupées par dossier. Cliquez sur n'importe quelle note pour accéder directement à ce dossier dans le Finder, l'exporter ou la supprimer.

### Interaction avec les notes
Survolez une note pour révéler sa barre d'action. De là, vous pouvez :
- Changer les couleurs de la note.
- Ajuster la taille de la police (A− / A+) et le style de police (Aa).
- Partager la note (via AirDrop, Messages, Mail, etc.).
- Supprimer la note.

Faites glisser la note par son arrière-plan pour la déplacer, ou par ses bordures pour la redimensionner. À l'intérieur de la note, utilisez `⌘ +` et `⌘ −` pour ajuster rapidement la taille du texte.

### Préférences
Depuis le menu de la barre, ouvrez les Préférences pour configurer :
- **Langue** : Basculez entre Portugais (Brésil), Anglais, Chinois, Japonais, Allemand ou Français.
- **Autorisation du Finder** : Gérez les autorisations d'automatisation Apple Events requises pour suivre la fenêtre Finder active.
- **Lancer au démarrage** : Choisissez si The Styk s'ouvre automatiquement au démarrage de votre Mac.
- **Sauvegardes** : Configurez des sauvegardes locales quotidiennes automatiques ou exportez/restaurez manuellement toutes les notes.

## FAQ

### Cela nécessite-t-il des autorisations spéciales ?
Oui. Au premier lancement, macOS demandera l'autorisation de contrôler le Finder. C'est nécessaire pour que The Styk puisse détecter quel dossier est actif et afficher ses notes respectives. Si vous refusez par erreur, vous pouvez déclencher à nouveau l'invite via Préférences -> bouton "Demander l'autorisation du Finder...".

### Que se passe-t-il lorsque je supprime une note ?
La suppression est entièrement réversible. Les notes supprimées vont dans la corbeille interne de l'application (accessible depuis la barre de menus) et sont automatiquement purgées après 5 jours.

### Que se passe-t-il si je déplace, renomme ou supprime un dossier ?
- **Dossiers déplacés/renommés** : The Styk utilise les signets de macOS, de sorte que les notes suivent automatiquement le dossier même si vous le renommez ou le déplacez vers un autre disque.
- **Dossiers supprimés** : Les notes ne sont pas perdues ; elles sont déplacées vers la section "Notes orphelines" du menu, où vous pouvez les ré-ancrer, les exporter ou les mettre à la corbeille.

### Cela fonctionne-t-il avec macOS 10.x ?
La version principale pour Apple Silicon nécessite macOS 11 (Big Sur) ou supérieur. Cependant, une version Intel héritée (legacy) est disponible et fonctionne sur macOS 10.13 (High Sierra) et supérieur.

### En quoi The Styk est-il différent des notes autocollantes standard ?
Contrairement aux applications de notes autocollantes standard où les notes encombrent votre bureau indéfiniment, The Styk ancre les notes de manière contextuelle à des dossiers spécifiques. Elles n'apparaissent que lorsque vous ouvrez et affichez réellement ce dossier dans le Finder.
