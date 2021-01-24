from flask import render_template, request, flash, redirect, url_for
from flask_login import login_required

import external_functions as ef
from decorators_filters import user_required

from webapp import app


@app.route('/view_user_places', methods=['GET'])
@login_required
@user_required
def view_user_places():
    page = request.args.get('page', 1, type=int)
    places = ef.get_user_places(page)
    print("length {}".format(len(places.items)))
    return render_template("view_user_places.html", places=places)


def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in app.config["ALLOWED_EXTENSIONS"]


@app.route('/load_takeout', methods=['POST'])
@login_required
def load_takeout():
    if 'file' not in request.files:
        flash('No file part')
        return redirect(request.url)
    file = request.files['file']
    # if user does not select file, browser also
    # submit an empty part without filename
    if file.filename == '':
        flash('No selected file')
        return redirect(request.url)
    if file and allowed_file(file.filename):
        current_user_id = ef.get_current_user_ID()
        ef.main_parser(current_user_id, file)
        flash("Il takeout è stato caricato correttamente!")
        return redirect(url_for("index"))