//! `GET /reservation/confirmer` — écran 3 du tunnel (« Vos informations »),
//! SSR (#5356). Page transactionnelle : le HTML initial reste indexable
//! (`h1` réel + texte de contexte) ; le formulaire/compte-à-rebours du hold
//! nécessite JS une fois la page chargée, hors scope de cette page vitrine.

use axum::response::Html;

use super::html::page;

pub async fn confirm_page() -> Html<String> {
    let body = r#"<h1>Vos informations</h1>
<p class="muted">Il ne reste qu'une étape</p>
<div class="context">
  <p>Votre créneau est retenu pendant quelques minutes. Créez votre compte Nubia pour confirmer le rendez-vous — vous pourrez ensuite gérer vos rendez-vous, documents et devis depuis le même compte, sans inscription supplémentaire.</p>
</div>"#;
    page("Confirmer votre rendez-vous — Nubia", body)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn renders_a_real_h1_and_context_paragraph() {
        let Html(html) = confirm_page().await;
        assert!(html.contains("<h1>Vos informations</h1>"));
        assert!(html.contains("class=\"context\""));
    }
}
