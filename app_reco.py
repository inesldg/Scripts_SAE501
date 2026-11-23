import os
import pickle
import numpy as np
from flask import Flask, request, jsonify

app = Flask(__name__)

#Chemin absolu vers reco.pkl pour éviter les erreurs de fichier non trouvé avec systemd
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CHEMIN_PKL = os.path.join(BASE_DIR, "reco.pkl")

#Chargé une seule fois, au démarrage du serveur
with open(CHEMIN_PKL, "rb") as f:
    reco = pickle.load(f)

produits = reco["produits"]
similarite = reco["sim_contenu"]
coAchat = reco["cooccurrence"]
ids = reco["ids"]

#Définition des fonctions de recommandation indispensables
def obtenir_reco_contenu(pid, n=5):
    if pid not in ids:
        return []
    i = ids.index(pid)
    scores = similarite[i].copy()
    scores[i] = -1
    top_indices = np.argsort(scores)[::-1][:n]
    
    recos = []
    for idx in top_indices:
        p_id = ids[idx]
        row = produits[produits["produit_id"] == p_id].iloc[0]
        recos.append({
            "produit_id": int(row["produit_id"]),
            "nom": row["nom"],
            "type_magie": row["type_magie"],
            "puissance": row["puissance"],
            "prix": float(row["prix"]),
            "score": float(round(scores[idx], 2))
        })
    return recos

def obtenir_reco_coachats(pid, n=5):
    if pid not in ids:
        return []
    i = ids.index(pid)
    scores = coAchat[i]
    top_indices = np.argsort(scores)[::-1]
    top_indices = top_indices[scores[top_indices] > 0][:n]
    
    recos = []
    for idx in top_indices:
        p_id = ids[idx]
        row = produits[produits["produit_id"] == p_id].iloc[0]
        recos.append({
            "produit_id": int(row["produit_id"]),
            "nom": row["nom"],
            "type_magie": row["type_magie"],
            "puissance": row["puissance"],
            "prix": float(row["prix"]),
            "achats_communs": int(scores[idx])
        })
    return recos

URL_AUTORISEES = {
  "https://ip87-106-3-165.pbiaas.com", 
  "https://ip87-106-123-60.pbiaas.com", 
  "http://87.106.123.60",               
  "https://87.106.123.60",
}

#Route API JSON pour l'intégration au site
@app.route("/api/recommander/<int:produit_id>")
def api_recommander(produit_id):
    n = request.args.get("n", default=4, type=int) #pour passer ?n=4 avec React
    n = max(1, min(n, 20))  # garde n entre 1 et 20 pour éviter des erreurs
  
    recos_contenu = obtenir_reco_contenu(produit_id, n=n)
    recos_coachat = obtenir_reco_coachats(produit_id, n=n)
    
    reponse = jsonify({
        "cible_id": produit_id,
        "recommandations_contenu": recos_contenu,
        "recommandations_coachat": recos_coachat
    })
    
    url = request.headers.get("Origin")
    if url in URL_AUTORISEES:
      reponse.headers.add("Access-Control-Allow-Origin", url)

    return reponse

if __name__ == "__main__":
    # host="0.0.0.0" : nécessaire pour que le tunnel proxy de Colab atteigne le serveur.
    app.run(host="0.0.0.0", port=8000)
