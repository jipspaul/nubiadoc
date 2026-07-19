//! Représentation d'un message HL7 v2 parsé : segments et accès aux champs
//! sans jamais paniquer, même sur un message malformé ou tronqué.
//!
//! Un seul type de segment générique (`Segment`) couvre tous les segments
//! (`MSH`, `PID`, `PV1`, `SCH`, `AIS`, `AIL`, `AIP`, ...) : l'accès aux champs se
//! fait par position 1-based via [`Segment::field`], [`Segment::component`], etc.
//! Seul `MSH` nécessite un traitement particulier à l'analyse, car il déclare
//! lui-même les caractères d'encodage du reste du message (voir `parser.rs`).

/// Caractères d'encodage déclarés en MSH-2 (`^~\&` par défaut).
///
/// Le séparateur de champ (MSH-1) n'est volontairement pas modélisé ici : la
/// norme HL7 v2 le fixe à `|` (voir `parser.rs::FIELD_SEP`), seuls les quatre
/// autres caractères sont variables et déclarés en MSH-2.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EncodingChars {
    /// Séparateur de composant (`^` par défaut).
    pub component: char,
    /// Séparateur de répétition (`~` par défaut).
    pub repetition: char,
    /// Caractère d'échappement (`\` par défaut). Non décodé par cette crate :
    /// les séquences d'échappement (`\F\`, `\S\`, ...) sont renvoyées telles
    /// quelles par les accesseurs de champs, à charge de l'appelant de les
    /// interpréter s'il en a besoin.
    pub escape: char,
    /// Séparateur de sous-composant (`&` par défaut).
    pub subcomponent: char,
}

impl Default for EncodingChars {
    fn default() -> Self {
        Self {
            component: '^',
            repetition: '~',
            escape: '\\',
            subcomponent: '&',
        }
    }
}

/// Un segment HL7 v2 : un identifiant 3 caractères (`MSH`, `PID`, ...) et une
/// liste de champs, indexée en 1-based conformément à la convention HL7.
///
/// Cas particulier `MSH` : par convention, le champ 1 (`field(1)`) vaut le
/// séparateur de champ lui-même (`"|"`) et le champ 2 (`field(2)`) vaut la
/// chaîne des quatre caractères d'encodage (`"^~\&"`) — ce sont les valeurs
/// littérales de MSH-1 et MSH-2 telles que définies par la norme.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Segment {
    id: String,
    fields: Vec<String>,
    encoding: EncodingChars,
}

impl Segment {
    pub(crate) fn new(id: String, fields: Vec<String>, encoding: EncodingChars) -> Self {
        Self {
            id,
            fields,
            encoding,
        }
    }

    /// Identifiant 3 caractères du segment (ex: `"PID"`).
    pub fn id(&self) -> &str {
        &self.id
    }

    /// Nombre de champs présents dans le segment (hors identifiant de segment).
    pub fn field_count(&self) -> usize {
        self.fields.len()
    }

    /// Champ `n` (1-based), valeur brute avec répétitions jointes par `~` si
    /// le champ en contient plusieurs. `None` si `n` est hors limites (jamais
    /// de panique, y compris pour `n == 0`).
    pub fn field(&self, n: usize) -> Option<&str> {
        let idx = n.checked_sub(1)?;
        self.fields.get(idx).map(String::as_str)
    }

    /// Répétition `repetition_n` (1-based) du champ `n`. Pour un champ sans
    /// répétition, `repetition_n == 1` renvoie le champ entier.
    pub fn repetition(&self, field_n: usize, repetition_n: usize) -> Option<&str> {
        let field = self.field(field_n)?;
        let idx = repetition_n.checked_sub(1)?;
        field.split(self.encoding.repetition).nth(idx)
    }

    /// Itère sur toutes les répétitions du champ `n` (séparées par `~`).
    /// `None` si le champ `n` n'existe pas.
    pub fn repetitions(&self, field_n: usize) -> Option<impl Iterator<Item = &str>> {
        let field = self.field(field_n)?;
        Some(field.split(self.encoding.repetition))
    }

    /// Composant `component_n` (1-based) de la première répétition du champ
    /// `field_n`. Pour accéder à un composant d'une répétition ultérieure
    /// (ex: un identifiant INS-NIR en 2e répétition de PID-3), voir
    /// [`Segment::component_in_repetition`].
    pub fn component(&self, field_n: usize, component_n: usize) -> Option<&str> {
        self.component_in_repetition(field_n, 1, component_n)
    }

    /// Composant `component_n` (1-based) de la répétition `repetition_n`
    /// (1-based) du champ `field_n`.
    pub fn component_in_repetition(
        &self,
        field_n: usize,
        repetition_n: usize,
        component_n: usize,
    ) -> Option<&str> {
        let rep = self.repetition(field_n, repetition_n)?;
        let idx = component_n.checked_sub(1)?;
        rep.split(self.encoding.component).nth(idx)
    }

    /// Sous-composant `subcomponent_n` (1-based) du composant `component_n`
    /// de la première répétition du champ `field_n`.
    pub fn subcomponent(
        &self,
        field_n: usize,
        component_n: usize,
        subcomponent_n: usize,
    ) -> Option<&str> {
        let comp = self.component(field_n, component_n)?;
        let idx = subcomponent_n.checked_sub(1)?;
        comp.split(self.encoding.subcomponent).nth(idx)
    }
}

/// Un message HL7 v2 : liste ordonnée de segments.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    segments: Vec<Segment>,
}

impl Message {
    pub(crate) fn new(segments: Vec<Segment>) -> Self {
        Self { segments }
    }

    /// Tous les segments du message, dans l'ordre d'apparition.
    pub fn segments(&self) -> &[Segment] {
        &self.segments
    }

    /// Premier segment dont l'identifiant correspond à `id` (ex: `"PID"`).
    pub fn segment(&self, id: &str) -> Option<&Segment> {
        self.segments.iter().find(|s| s.id() == id)
    }

    /// Tous les segments dont l'identifiant correspond à `id` — utile pour les
    /// segments pouvant se répéter dans un même message (ex: plusieurs `AIS`
    /// dans un `SIU^S12` avec plusieurs ressources).
    pub fn segments_with_id(&self, id: &str) -> Vec<&Segment> {
        self.segments.iter().filter(|s| s.id() == id).collect()
    }
}
