"""
    Varie funzioni utilizzate nelle route web e altrove

"""

import codecs
from datetime import datetime

from flask_login import current_user
from problog.extern import problog_export
from problog.logic import Term, Constant
from problog.program import PrologString, PrologFile
from problog.formula import LogicFormula, LogicDAG
from problog.cnf_formula import CNF
from problog.ddnnf_formula import DDNNF

import json
import random

from config import engine

from models import *

from webapp import db, app


# Funzione che stabilisce se un luogo è al chiuso o all'aperto in base alle parole contenute nel nome
# Questa funzione può essere migliorata ulteriormente in sviluppi futuri aggiungendo nuovi termini chiavi
# o con un metodo più sofisticato
def indoor_check(name):
    cases = ["piazza", "via", "parco", "fontana", "laghetti", "parcheggio"]
    for case in cases:
        if case in name.casefold():
            return 0
    return 1


# Parser del file Json Google Takeout
# uid: Id dell'utente
# file: File del Json (caricato con open() o come nel nostro caso passato tramite form)
# Vengono scartati i placeVisit più vecchi di 30 giorni dalla data odierna
def main_parser(uid, file):
    try:
        json_dict = json.load(file)
        for obj in json_dict['timelineObjects']:
            # place(CF, Ti(integer), Lat, Long, Tf(integer), placeId).
            location = obj['placeVisit']['location']
            duration = obj['placeVisit']['duration']
            prev = datetime.now().timestamp() - 2592000
            if int(duration["endTimestampMs"]) / 1000 > prev:
                p = Place(id=uid,
                          start=duration["startTimestampMs"],
                          lat=location["latitudeE7"],
                          long=location["longitudeE7"],
                          finish=duration["endTimestampMs"],
                          placeId=location["name"],
                          indoor=indoor_check(location["name"]))
                db.session.add(p)
        db.session.commit()
    except:
        return False
    return True


# Funzione che richiama Problog per inserire un positivo e generare i nodi rossi
# user_id: Id dell'utente
# date: Data del tampone in millisecondi
def call_prolog_insert_positive(user_id, date):
    p = ""
    # main_sanita.pl è in utf-16
    with codecs.open("prolog/main_sanita.pl", "r", "utf-16") as f:
        for line in f:
            p += line

    p = PrologString(p)  # Creazione di un programma Problog
    dbp = engine.prepare(p)  # Preparazione del programma in un formato comodo per l'engine Problog
    # Data del nodo rosso più vecchio con cui ha avuto un contatto
    oldest_match = User.query.get(user_id).oldest_risk_date
    if oldest_match is None:
        oldest_match = 0
    query = Term("insertPositive", Constant(user_id), Constant(date), Constant(oldest_match))
    res = engine.query(dbp, query)  # Esecuzione della query


# Trova la probabilità di tutti
def find_all_prob():
    ps = ""
    with open("prolog/problog_predicates.pl", "r") as f:
        for line in f:
            ps += line

    # Calcolo probabilità tramite problog
    ps += "query(infect(_))."
    p = PrologString(ps)
    dbp = engine.prepare(p)
    lf = LogicFormula.create_from(p)  # ground the program
    dag = LogicDAG.create_from(lf)  # break cycles in the ground program
    cnf = CNF.create_from(dag)  # convert to CNF
    ddnnf = DDNNF.create_from(cnf)  # compile CNF to ddnnf
    r = ddnnf.evaluate()

    # Siccome Problog restituisce un dizionario struttrato in questa maniera:
    # {query(infect(2)): 0.67, query(infect(3)): 0.8, ...}
    # Bisogna estrarre ogni id dalla chiave nel seguente modo
    items = []
    if len(RedNode.query.all()) > 0:
        for key, value in r.items():
            start = "infect("
            end = ")"
            result = str(key)[len(start):-len(end)]
            try:
                u = User.query.get(int(result))
                items.append((u, value))
            except ValueError:
                continue
    return items


# Trova la probabilità di un singolo individuo
def find_user_prob(uid):
    ps = ""
    with open("prolog/problog_predicates.pl", "r") as f:
        for line in f:
            ps += line

    # Pulizia dei nodi dinamici date/1 all'interno di problog
    p = PrologString(ps)
    dbp = engine.prepare(p)
    query = Term("clean")
    res = engine.query(dbp, query)

    # Calcolo probabilità tramite problog
    ps += "query(infect(" + str(uid) + "))."
    p = PrologString(ps)
    dbp = engine.prepare(p)
    lf = LogicFormula.create_from(p)  # ground the program
    dag = LogicDAG.create_from(lf)  # break cycles in the ground program
    cnf = CNF.create_from(dag)  # convert to CNF
    ddnnf = DDNNF.create_from(cnf)  # compile CNF to ddnnf
    r = ddnnf.evaluate()

    # Salvataggio nel database SQLite della data del nodo rosso più vecchio con cui è stato a contatto
    term = Term("date", None)
    database = problog_export.database  # Database interno di Problog dove vengono salvati i fatti con assertz()
    node_key = database.find(term)
    if node_key is not None:
        node = database.get_node(node_key)
        dates = node.children.find(term.args)  # Tutti i fatti date/1 inseriti con assertz/1
        vals = []
        if dates:
            for date in dates:
                n = database.get_node(date)
                vals.append(int(n.args[0]))
        min_val = min(vals)  # Trova la data (in millisecondi) minima
        u = User.query.get(uid)
        u.oldest_risk_date = min_val
        db.session.commit()

    return r


# Ottieni tutti i nodi place
def get_places():
    return Place.query.all()


# Ottieni i place di un utente con la paginazione
def get_user_places(page):
    print(current_user.get_id())
    return Place.query.filter_by(id=current_user.get_id()).paginate(page=page, per_page=app.config["NODES_PER_PAGE"])


# Ottieni tutti i nodi rossi
def get_red_nodes():
    return RedNode.query.all()


# Ottieni tutti gli utenti
def get_users():
    return User.query.all()


# Imposta l'utente come positivo nel database
# id: Id dell'utente
# date: Data del tampone in millisecondi
def set_user_positive(uid, date):
    u = User.query.get(uid)
    u.positive = True
    u.test_date = date
    db.session.commit()


# Restituisce la positività di un utente
def is_positive(uid):
    u = User.query.get(uid)
    return u.positive


# Restituisce la positività di un utente passando il codice fiscale
def is_positive_through_cf(cf):
    u = User.query.filter_by(cf=cf).first()
    return u.positive


# Scrive nel database un nodo rosso
def add_rednode(prob, start, lat, long, finish, place):
    exists = db.session.query(db.exists().where(RedNode.start == start and RedNode.placeId == place)).scalar()
    if not exists:
        r = RedNode(prob=prob, start=start, lat=lat, long=long, finish=finish, placeId=place)
        db.session.add(r)
        db.session.commit()
    else:
        print("Instance already exists")


# Aggiunge un utente al database
def add_user(user):
    db.session.add(user)
    db.session.commit()


# Aggiorna un utente
def update_user(user_id, username, email, cf):
    user = User.query.get(int(user_id))
    user.username = username
    user.email = email
    user.cf = cf
    db.session.commit()


# Elimina un utente nell database
def delete_user(user_id):
    user = User.query.get(int(user_id))
    db.session.delete(user)
    db.session.commit()


# Elimina tutti i nodi verdi
def clean_green_nodes():
    gnodes = Place.query.all()
    for g in gnodes:
        db.session.delete(g)
    db.session.commit()


# Elimina tutti i nodi verdi di un utente
def clean_user_green_nodes(uid):
    gnodes = Place.query.filter_by(id=uid).all()
    for g in gnodes:
        db.session.delete(g)
    db.session.commit()


# Elimina tutti i nodi rossi
def clean_red_nodes():
    rnodes = RedNode.query.all()
    for r in rnodes:
        db.session.delete(r)
    db.session.commit()


# Rimette tutti gli utenti a negativo
def reset_all_users():
    users = User.query.all()
    for u in users:
        u.positive = False
        u.test_date = None
        u.oldest_risk_date = None
    db.session.commit()


# Rimette un utente a negativo
def reset_user(uid):
    u = User.query.get(uid)
    u.positive = False
    u.test_date = None
    u.oldest_risk_date = None
    db.session.commit()


# Ottiene l'id dell'utente corrente
# Altrimenti usare semplicemente current_user.id
def get_current_user_ID():
    internal_id = current_user.get_id()
    user = load_user(internal_id)
    return user.id


# Ottiene l'id dell'utente con un dato codice fiscale
def get_user_ID(cf):
    user = User.query.filter_by(cf=cf).first()
    return user.id


# Ottiene l'username dell'utente corrente
# Altrimenti usare semplicemente current_user.username
def get_current_username():
    internal_id = current_user.get_id()
    user = load_user(internal_id)
    return user.username


# Avvia la funzione per il calcolo della probabilità di un utente per l'utente corrente
def get_current_prob():
    uid = get_current_user_ID()
    r = find_user_prob(uid)
    ls = list(r.keys())  # Bisogna manualmente estrarre la chiave perchè è un oggetto anziche stringa
    return r[ls[0]]


# Genera un numero random tra -50 e 50 per variare le coordinate GPS nella funzione generate_random_takeout()
def rand_loc():
    return random.randrange(-50, 50)


# Funzione che genera un Google Takeout random per il testing
# Vedere l'array in fondo per aggiungere o rimuovere i luoghi di test
def generate_random_takeout():
    random.seed()
    dt_obj = datetime.now()
    # dt_obj = datetime.strptime("2020-01-01 12:00", '%Y-%m-%d %H:%M')
    start_time = int((dt_obj.timestamp() - 432000) * 1000)
    time_step = 900000  # 15 minuti in millisecondi
    start_time += random.randrange(0, 8) * time_step

    timeline = []
    for i in range(30):
        place = random.choice(places)
        elem = {"placeVisit": {
            "location": {
                "latitudeE7": place[1] + rand_loc(),
                "longitudeE7": place[2] + rand_loc(),
                "name": place[0]
            },
            "duration": {
                "startTimestampMs": start_time,
                "endTimestampMs": start_time + random.randrange(1, 8) * time_step
            }
        }}
        timeline.append(elem)
        start_time += random.randrange(9, 32) * time_step
    obj = {"timelineObjects": timeline}
    return json.dumps(obj)


places = [("Via G. Spataro, 14", 426775091, 137287389,),
          ("Marche Polytechnic University - Faculty of Engineering", 435867790, 135165950),
          ("Teatro Sperimentale", 436135866, 135152479,),
          ("Med Store Ancona", 436175400, 135152900),
          ("Pizzeria Paola Ancona", 436178800, 135155200),
          ("Piazza del Plebiscito", 436195700, 135118400),
          ("Cattedrale di San Ciriaco", 436253900, 135103000),
          ("Fontana dei due Soli", 436251700, 135032000),
          ("Rustico Ristorante Pizzeria", 435855700, 135176300),
          ("La Cittadella di Ancona", 436111400, 135126900),
          ("Laghetti del Passetto - Parco Pubblico", 436134400, 135364800),
          ("Parcheggio Stamira", 436161600, 135154400),
          ("C.M.E. Marche", 436160000, 135107000),
          ("CONAD", 436147000, 135298100)]
