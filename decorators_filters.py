"""
    Decoratori (annotazioni) per definire i permessi di accesso in base al campo 'role' di un utente
    e template filter per formattare diversamente alcuni valori negli HTML

"""

from functools import wraps

from flask import flash, redirect, url_for
from flask_login import current_user
from datetime import datetime
from webapp import app
import numpy as np


# Decoratore per i permessi di admin, utilizzato nelle rotte definite in admin.py
def admin_required(func):
    @wraps(func)
    def wrap(*args, **kwargs):
        if current_user.role == "admin":
            return func(*args, **kwargs)
        else:
            flash("Non hai i permessi per accedere a questa pagina")
            return redirect(url_for('index'))
    return wrap


# Decoratore per i permessi di operatore sanitario, utilizzato nelle rotte definite in health_worker.py
def health_required(func):
    @wraps(func)
    def wrap(*args, **kwargs):
        if current_user.role == "health":
            return func(*args, **kwargs)
        else:
            flash("Non hai i permessi per accedere a questa pagina")
            return redirect(url_for('index'))
    return wrap


# Decoratore per i permessi di utente standard, utilizzato nelle rotte definite in user.py
def user_required(func):
    @wraps(func)
    def wrap(*args, **kwargs):
        if current_user.role == "user":
            return func(*args, **kwargs)
        else:
            flash("Non hai i permessi per accedere a questa pagina")
            return redirect(url_for('index'))

    return wrap


# Filtro HTML per convertire il tempo da millisecondi a datetime
@app.template_filter('ctime')
def timectime(s):
    if s is not None:
        s = int(s / 1000)
        return datetime.fromtimestamp(s)
    return "N/A"


# Filtro HTML per stampare Si o No a seconda della positività
@app.template_filter('pos_translation')
def pos_tr(p):
    if p:
        return "Si"
    return "No"


# Filtro HTML per stampare la probabilità in percentuale
@app.template_filter('cut_prob')
def cut_prob(prob):
    prob *= 100
    return "{:.2f} %".format(prob)


# Filtro HTML per convertire le coordinate
@app.template_filter('coord')
def cut_prob(coord):
    coord = np.double(coord) / 1E7
    return coord
