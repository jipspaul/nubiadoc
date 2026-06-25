//! Canal abstraction + Hub de broadcast in-process (WS-B.a).
#![forbid(unsafe_code)]

use std::{collections::HashMap, sync::Mutex};
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};
use uuid::Uuid;

/// Envelope envoyée aux abonnés WebSocket.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ServerEnvelope {
    pub op: String,
    pub channel: String,
    pub data: serde_json::Value,
}

/// Canaux WebSocket disponibles.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Channel {
    WaitingRoom { cabinet_id: Uuid },
}

/// Parse un nom de canal et ses paramètres JSON.
///
/// # Errors
/// Retourne une erreur si le canal est inconnu ou si un paramètre requis est absent/invalide.
pub fn parse_channel(s: &str, params: serde_json::Value) -> anyhow::Result<Channel> {
    match s {
        "waiting_room" => {
            let cabinet_id = params
                .get("cabinet_id")
                .and_then(|v| v.as_str())
                .and_then(|id| Uuid::parse_str(id).ok())
                .ok_or_else(|| anyhow::anyhow!("missing or invalid cabinet_id"))?;
            Ok(Channel::WaitingRoom { cabinet_id })
        }
        other => Err(anyhow::anyhow!("unknown channel: {other}")),
    }
}

/// Hub de broadcast in-process partagé via `Arc<Hub>`.
///
/// Chaque appel à `subscribe` crée un canal `unbounded_channel` dédié.
/// `publish` envoie une copie de l'envelope à tous les abonnés vivants et
/// purge les senders fermés.
pub struct Hub {
    senders: Mutex<HashMap<Channel, Vec<UnboundedSender<ServerEnvelope>>>>,
}

impl Default for Hub {
    fn default() -> Self {
        Self::new()
    }
}

impl Hub {
    pub fn new() -> Self {
        Self {
            senders: Mutex::new(HashMap::new()),
        }
    }

    /// Souscrit au canal ; retourne un `UnboundedReceiver` pour recevoir les envelopes.
    pub fn subscribe(&self, channel: Channel) -> UnboundedReceiver<ServerEnvelope> {
        let (tx, rx) = unbounded_channel();
        let mut map = self.senders.lock().unwrap_or_else(|e| e.into_inner());
        map.entry(channel).or_default().push(tx);
        rx
    }

    /// Publie une envelope vers tous les abonnés du canal.
    /// Les senders dont le receiver a été abandonné sont automatiquement purgés.
    pub fn publish(&self, channel: &Channel, envelope: ServerEnvelope) {
        let mut map = self.senders.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(senders) = map.get_mut(channel) {
            senders.retain(|tx| tx.send(envelope.clone()).is_ok());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn make_envelope() -> ServerEnvelope {
        ServerEnvelope {
            op: "queue_updated".into(),
            channel: "waiting_room".into(),
            data: json!({"count": 3}),
        }
    }

    #[test]
    fn parse_waiting_room_ok() {
        let id = Uuid::new_v4();
        let ch = parse_channel("waiting_room", json!({"cabinet_id": id.to_string()})).unwrap();
        assert_eq!(ch, Channel::WaitingRoom { cabinet_id: id });
    }

    #[test]
    fn parse_waiting_room_missing_cabinet_id() {
        assert!(parse_channel("waiting_room", json!({})).is_err());
    }

    #[test]
    fn parse_unknown_channel() {
        assert!(parse_channel("unknown", json!({})).is_err());
    }

    #[tokio::test]
    async fn subscribe_and_publish() {
        let hub = Hub::new();
        let cabinet_id = Uuid::new_v4();
        let channel = Channel::WaitingRoom { cabinet_id };

        let mut rx = hub.subscribe(channel.clone());
        hub.publish(&channel, make_envelope());

        let received = rx.recv().await.unwrap();
        assert_eq!(received.op, "queue_updated");
    }

    #[tokio::test]
    async fn publish_cleans_dead_senders() {
        let hub = Hub::new();
        let cabinet_id = Uuid::new_v4();
        let channel = Channel::WaitingRoom { cabinet_id };

        {
            // rx dropped immediately — sender becomes dead
            let _rx = hub.subscribe(channel.clone());
        }
        // Should not panic, should purge the dead sender
        hub.publish(&channel, make_envelope());

        let map = hub.senders.lock().unwrap();
        let senders = map.get(&channel).unwrap();
        assert!(senders.is_empty());
    }

    #[tokio::test]
    async fn multiple_subscribers_all_receive() {
        let hub = Hub::new();
        let cabinet_id = Uuid::new_v4();
        let channel = Channel::WaitingRoom { cabinet_id };

        let mut rx1 = hub.subscribe(channel.clone());
        let mut rx2 = hub.subscribe(channel.clone());
        hub.publish(&channel, make_envelope());

        assert_eq!(rx1.recv().await.unwrap().op, "queue_updated");
        assert_eq!(rx2.recv().await.unwrap().op, "queue_updated");
    }

    #[tokio::test]
    async fn publish_no_subscribers_is_noop() {
        let hub = Hub::new();
        let cabinet_id = Uuid::new_v4();
        let channel = Channel::WaitingRoom { cabinet_id };
        // Should not panic
        hub.publish(&channel, make_envelope());
    }
}
