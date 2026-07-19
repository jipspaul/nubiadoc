//! Codec MLLP (Minimal Lower Layer Protocol) : encadre chaque message HL7 v2
//! avec `0x0B` (start block) ... `0x1C 0x0D` (end block + CR).
//!
//! Générique sur `AsyncRead`/`AsyncWrite` (pas seulement `TcpStream`), ce qui
//! permet de tester le framing avec `tokio::io::duplex()` sans socket réel.
//! Ne fait aucune hypothèse réseau/TLS : c'est un lot séparé (B5) qui branche
//! ce codec sur un vrai listener TCP.

use std::time::Duration;

use thiserror::Error;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::time::timeout;

const START_BLOCK: u8 = 0x0B;
const END_BLOCK: u8 = 0x1C;
const CARRIAGE_RETURN: u8 = 0x0D;

/// Erreur de trame MLLP. Toujours renvoyée en `Err`, jamais de panique — y
/// compris sur une connexion qui se ferme, une trame trop grosse, ou une
/// trame malformée.
#[derive(Debug, Error)]
pub enum MllpError {
    /// La connexion s'est fermée avant qu'une trame complète soit reçue.
    #[error("connexion fermée avant réception d'une trame complète")]
    ConnectionClosed,
    /// La trame dépasse `max_frame_len` avant d'avoir vu le bloc de fin.
    #[error("trame dépasse la taille maximale autorisée ({max} octets)")]
    FrameTooLarge {
        /// Taille maximale configurée qui a été dépassée.
        max: usize,
    },
    /// Aucune trame complète n'est arrivée avant `read_timeout`.
    #[error("délai d'attente dépassé en lisant la trame")]
    Timeout,
    /// Erreur d'E/S sous-jacente (autre qu'une fermeture propre de connexion).
    #[error("erreur d'entrée/sortie : {0}")]
    Io(#[from] std::io::Error),
    /// Un nouveau bloc de début (`0x0B`) est arrivé avant que la trame
    /// précédente ne soit close par `0x1C 0x0D` : framing malformé.
    #[error("bloc de début (0x0B) reçu avant la clôture de la trame précédente")]
    UnexpectedStartBlock,
    /// Le bloc de fin (`0x1C`) n'a pas été suivi du retour chariot (`0x0D`)
    /// attendu : framing malformé.
    #[error("bloc de fin (0x1C) non suivi du retour chariot (0x0D) attendu")]
    MissingTerminator,
}

/// Options de lecture d'une trame MLLP : garde-fou de taille et timeout.
#[derive(Debug, Clone, Copy)]
pub struct MllpReadOptions {
    /// Taille maximale (en octets) du contenu du message, hors marqueurs.
    /// Protège contre une croissance non bornée du buffer si l'émetteur est
    /// défaillant ou malveillant. Défaut : 1 MiB.
    pub max_frame_len: usize,
    /// Délai maximal pour recevoir une trame complète (attente du start
    /// block incluse). Protège contre une connexion qui reste ouverte sans
    /// jamais envoyer de trame complète. Défaut : 30s.
    pub read_timeout: Duration,
}

impl Default for MllpReadOptions {
    fn default() -> Self {
        Self {
            max_frame_len: 1024 * 1024,
            read_timeout: Duration::from_secs(30),
        }
    }
}

/// Lit une trame MLLP complète depuis `reader` : attend `0x0B`, accumule les
/// octets jusqu'à `0x1C` suivi de `0x0D`, puis renvoie le contenu du message
/// (sans les marqueurs). Respecte `options.max_frame_len` et
/// `options.read_timeout`.
pub async fn read_frame<R>(reader: &mut R, options: MllpReadOptions) -> Result<Vec<u8>, MllpError>
where
    R: AsyncRead + Unpin,
{
    match timeout(
        options.read_timeout,
        read_frame_inner(reader, options.max_frame_len),
    )
    .await
    {
        Ok(result) => result,
        Err(_elapsed) => Err(MllpError::Timeout),
    }
}

async fn read_byte<R>(reader: &mut R) -> Result<u8, MllpError>
where
    R: AsyncRead + Unpin,
{
    match reader.read_u8().await {
        Ok(b) => Ok(b),
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => Err(MllpError::ConnectionClosed),
        Err(e) => Err(MllpError::Io(e)),
    }
}

async fn read_frame_inner<R>(reader: &mut R, max_frame_len: usize) -> Result<Vec<u8>, MllpError>
where
    R: AsyncRead + Unpin,
{
    // Attend le start block, en ignorant tout octet parasite avant.
    loop {
        let b = read_byte(reader).await?;
        if b == START_BLOCK {
            break;
        }
    }

    // Accumule jusqu'à voir END_BLOCK suivi de CR.
    let mut buf = Vec::new();
    loop {
        let b = read_byte(reader).await?;
        if b == START_BLOCK {
            return Err(MllpError::UnexpectedStartBlock);
        }
        if b == END_BLOCK {
            let cr = read_byte(reader).await?;
            if cr != CARRIAGE_RETURN {
                return Err(MllpError::MissingTerminator);
            }
            return Ok(buf);
        }
        if buf.len() >= max_frame_len {
            return Err(MllpError::FrameTooLarge { max: max_frame_len });
        }
        buf.push(b);
    }
}

/// Écrit `message` (octets bruts du message HL7, sans marqueurs) enveloppé
/// dans le cadre MLLP `0x0B ... 0x1C 0x0D` sur `writer`.
pub async fn write_frame<W>(writer: &mut W, message: &[u8]) -> Result<(), MllpError>
where
    W: AsyncWrite + Unpin,
{
    writer.write_u8(START_BLOCK).await?;
    writer.write_all(message).await?;
    writer.write_u8(END_BLOCK).await?;
    writer.write_u8(CARRIAGE_RETURN).await?;
    writer.flush().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::duplex;

    #[tokio::test]
    async fn round_trip_message_through_writer_and_reader() {
        let (mut a, mut b) = duplex(4096);
        let payload = b"MSH|^~\\&|A|B|C|D|20260719||ADT^A28|1|P|2.5\rPID|1\r";

        write_frame(&mut a, payload)
            .await
            .expect("write must succeed");
        let received = read_frame(&mut b, MllpReadOptions::default())
            .await
            .expect("read must succeed");

        assert_eq!(received, payload);
    }

    #[tokio::test]
    async fn back_to_back_messages_on_same_connection_both_parse() {
        let (mut a, mut b) = duplex(8192);
        let first = b"MSH|^~\\&|A|B|C|D|20260719||ADT^A28|1|P|2.5\r";
        let second = b"MSH|^~\\&|A|B|C|D|20260719||ADT^A31|2|P|2.5\r";

        write_frame(&mut a, first)
            .await
            .expect("write 1 must succeed");
        write_frame(&mut a, second)
            .await
            .expect("write 2 must succeed");

        let got_first = read_frame(&mut b, MllpReadOptions::default())
            .await
            .expect("read 1 must succeed");
        let got_second = read_frame(&mut b, MllpReadOptions::default())
            .await
            .expect("read 2 must succeed");

        assert_eq!(got_first, first);
        assert_eq!(got_second, second);
    }

    #[tokio::test]
    async fn oversized_frame_is_rejected() {
        let (mut a, mut b) = duplex(8192);
        let payload = vec![b'A'; 500];

        write_frame(&mut a, &payload)
            .await
            .expect("write must succeed");

        let options = MllpReadOptions {
            max_frame_len: 16,
            ..MllpReadOptions::default()
        };
        let result = read_frame(&mut b, options).await;
        assert!(matches!(result, Err(MllpError::FrameTooLarge { max: 16 })));
    }

    #[tokio::test]
    async fn frame_with_no_terminator_times_out_cleanly() {
        let (mut a, mut b) = duplex(4096);
        // Démarre une trame mais ne l'achève jamais.
        a.write_all(&[START_BLOCK, b'A', b'B', b'C'])
            .await
            .expect("write must succeed");

        let options = MllpReadOptions {
            max_frame_len: 1024,
            read_timeout: Duration::from_millis(50),
        };
        let result = read_frame(&mut b, options).await;
        assert!(matches!(result, Err(MllpError::Timeout)));
    }

    #[tokio::test]
    async fn stray_start_block_before_previous_frame_closed_is_an_error() {
        let (mut a, mut b) = duplex(4096);
        a.write_all(&[START_BLOCK, b'A', b'A', b'A', START_BLOCK])
            .await
            .expect("write must succeed");

        let result = read_frame(&mut b, MllpReadOptions::default()).await;
        assert!(matches!(result, Err(MllpError::UnexpectedStartBlock)));
    }

    #[tokio::test]
    async fn connection_closed_before_frame_complete_is_an_error() {
        let (mut a, mut b) = duplex(4096);
        a.write_all(&[START_BLOCK, b'A', b'B'])
            .await
            .expect("write must succeed");
        drop(a); // ferme le côté écriture, provoque un EOF côté lecture.

        let result = read_frame(&mut b, MllpReadOptions::default()).await;
        assert!(matches!(result, Err(MllpError::ConnectionClosed)));
    }
}
