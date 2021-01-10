% nodorosso è utilizzato per tenere traccia dei nuovi nodi rossi da
% inserire:
%    nodorosso(PROB_CONT,TIMEINIZIO,LAT,LONG,TIMEFINE,IDPLACE).
%
% database è utilizzato come database di appoggio dei nodi rossi che già
% esistevano per poter filtrarli e poterli reinserire in un file alla
% fine insieme ai nuovi nodi rossi:
%    database(PROB_CONT,TIMEINIZIO,TIMEFINE,IDPLACE).
%
% nodo è per salvare tutti gli utenti che hanno dei nodi verdi che
% matchano con nodi rossi inseriti su db.pl. Alla fine vengono
% effettuate le somme su nodi con ID_INDIVIDUO uguali:
%    nodo(ID_INDIVIDUO,PROB_CONT).
% -sigmoid((10-a)/k) -sigmoid((20-a)/k)*1.267 + sigmoid((10-a)/k)*sigmoid((20-a)/k)*0.76 = -sigmoid((30-a)/k) -sigmoid((10-a)/k)*0.667 + sigmoid((10-a)/k)*sigmoid((30-a)/k)*0.4
:-[predicati].

:-dynamic nodorosso/6.
:-dynamic database/6.

:- use_module('custom_predicates.py').
:- use_module(library(lists)).
:- use_module(library(db)).
:- sqlite_load('app.db').


% inserimento di un individuo positivo
%
insertPositive(Id, Date):-
    % pulizia record di appoggio
    retractall(nodorosso(_,_,_,_,_,_)),
    retractall(database(_,_,_,_)),

    findall(_,scorriDb,_),

    findall([Ti,La,Lo,Tf,Place],place(Id,Ti,La,Lo,Tf,Place),ListaPlace),  % TUTTI I POSTI IN CUI è STATO IL POSITIVO

    syncPlace(Date,ListaPlace),
    findall([Pnr,Tinr,Lanr,Lonr,Tfnr],nodorosso(Pnr,Tinr,Lanr,Lonr,Tfnr,_),Nodi),

    % Aggiunge tutti i nodi rossi vecchi nel database
    findall(_,insertOldNodesDb,_),
    % Aggiunge tutti i nodi rossi nuovi nel database
    insertNewNodesDb(Nodi).

% salva tutti i vecchi nodi rossi nel database dinamico di appoggio.
%
scorriDb :-
    db(P,Ti,La,Lo,Tf,Pl),
    assert(database(P,Ti,La,Lo,Tf,Pl)).

% finchè esistono dei nodi verdi per quell'ID_INDIVIDUO continua a
% matchare con questo predicato.
% Trova la giusta PROB_CONT da associare a quel nodo e cerca se ci sono
% nodi rossi esistenti che si sovrappongono attraverso syncDB.
% Poi inserisce il nuovo nodo rosso e i nodi delle ore successive
% attraverso addSucc.
% Dt = Data tampone
%
syncPlace(_,[]).
syncPlace(Dt,[[Ti,La,Lo,Tf,Place]|ListaPlace]):-
    c(Dt,Tf,P),                % ANCHE QUESTA FUNZIONE VA SICURAMENTE CAMBIATA
    checkP(P,X),               % X="ok" -> avanti; X="stop" -> prob trascurabile

    syncDb(X,P,Ti,La,Lo,Tf,Place),   % UN NODO VERDE ALLA VOLTA

    addSucc(X,P,Tf,La,Lo,Place),

    syncPlace(Dt,ListaPlace).  % Chiamata ricorsiva

% per aggiungere i nodi rossi successivi al nodo verde preso dal file.
% 2 ore successive al tempo di fine con PROB_CONT decrescente del 30%
% ogni volta, fino a quando non diventa trascurabile -> "stop".
%
% ad ogni iterazione viene ricontrollato tutto il procedimento per
% controllare se si sovrappone ad un nodo già esistente.
%
addSucc("stop",_,_,_).
addSucc("ok",P,Ti,La,Lo,Place):-
    Tf is Ti+7200000,
    Prob is P-0.3,
    checkP(Prob,X),
    syncDb(X,Prob,Ti,La,Lo,Tf,Place),
    addSucc(X,Prob,Tf,La,Lo,Place).

% richiama i predicati per sincronizzare i nodi rossi esistenti con il
% nodo verde preso in considerazione nel ciclo corrente
syncDb(X,P,Ti,La,Lo,Tf,Place):-
    joinList(X,Place,La,Lo,AllTempi,L),
    joinTime(P,Ti,La,Lo,Tf,Place,AllTempi),
    findall(Pr,nodorosso(Pr,_,_,_,_,Place),ListaNr),
    length(ListaNr,L2),
    nojoin(L,L2,P,Ti,La,Lo,Tf,Place).

% prende tutti i nodi vecchi e nuovi che hanno come place il luogo del
% nodo verde preso in considerazione e li inserisce in una lista per
% poterli scorrere tutti
% Se X="stop" restituisce la lista vuota così si procede con il
% successivo nodo verde
% POSSIAMO OTTIMIZZARLO PASSANDO I TEMPI
joinList("stop",_,_,_,[],"stop").
joinList("ok",Place,La,Lo,Tempi,L):-
    % close/4 FUNZIONE PYTHON
    findall(["db",Tidb,Ladb,Lodb,Tfdb,Pdb],(database(Pdb,Tidb,Ladb,Lodb,Tfdb,Place), close(La,Lo,Ladb,Lodb)),TempiDb),
    findall(["nr",Tinr,Lanr,Lonr,Tfnr,Pnr],(nodorosso(Pnr,Tinr,Lanr,Lonr,Tfnr,Place), close(La,Lo,Ladb,Lodb)),TempiNr),
    length(TempiNr,L),
    append(TempiDb,TempiNr,Tempi).

% predicato ricorsivo, scorre tutti i nodi rossi vecchi e nuovi trovati
% e vede se i tempi coincidono con il nodo verde corrente.
% Si calcolano gli intervalli nel predicato t e vengono inseriti i nuovi
% nodi.
% P1 Ti Tf sono del nodo verde
joinTime(_,_,_,_,[]).
joinTime(P1,Ti,La,Lo,Tf,Place,[[Tipo,Ti2,La2,Lo2,Tf2,P2]|AllTempi]):-
    ProbNew is 1-((1-P1)*(1-P2)),
    t(Place,Ti,La,Lo,Tf,Ti2,La2,Lo2,Tf2,P1,P2,ProbNew,X),  %CREA 3 o 2 nodirossi\6
    deleteOld(X,Tipo,Ti2,Tf2,Place,P2),
    joinTime(P1,Ti,La,Lo,Tf,Place,AllTempi).

% se si trova una corrispondenza nei tempi su joinTime e vengono
% inseriti altri nodi allora si elimina il nodo rosso che coincideva
% (può essere vecchio "db" oppure nuovo "nr")
% se non c'è nessuna corrispondenza ("no") non viene eliminato nessun
% nodo
%
deleteOld("no",_,_,_,_,_).
deleteOld("si","db",Ti,Tf,Place,P):-
    retract(database(P,Ti,_,_,Tf,Place)).
deleteOld("si","nr",Ti,Tf,Place,P):-
    retract(nodorosso(P,Ti,_,_,Tf,Place)).
deleteOld(_,_,_,_,_).

% quando sono stati scorsi tutti i nodi rossi vecchi e nuovi si
% considera il caso in cui nessuno di questi sia coincidente con il nodo
% che si sta inserendo, in quel caso s'inserisce il nodo verde.
% Si controlla questa coincidenza con la cardinalità di nodorosso prima
% e dopo di chiamare joinTime
% L2 LUNGHEZZA LISTA NODI ROSSI NUOVI DOPO joinTime
%
nojoin("stop",_,_,_,_,_,_,_).
nojoin(L,L2,_,_,_,_,_,_):-
    \+ L = "stop",
    L2>L.
nojoin(L,L,P,Ti,La,Lo,Tf,Place):-
    \+ L = "stop",
    L2 = L,
    assert(nodorosso(P,Ti,La,Lo,Tf,Place)).

% inserimento dei nodi rossi vecchi nel file db.pl.
% S è lo stream che è stato aperto prima.
% Vengono inoltre filtrati dai nodi con più di 30 giorni dalla data
% corrente grazie a Tf>Limite.
%
insertOldNodesDb:-
    database(P,Ti,Lat,Long,Tf,Pl),
    % TODO cambiare con una funzione python get_time(Curr),
    % Limite is (Curr-2592000)*1000,
    % Tf>Limite,
    add_rednode(P,Ti,Lat,Long,Tf,Pl).   % FUNZIONE PYTHON

% inserimento di tutti i nuovi nodi rossi nel database.
% Si scorre la lista di tutti i nodi che sono stati trovati, poi ogni
% volta che ne viene inserito uno nuovo viene anche eliminato dal
% database dinamico.
%
insertNewNodesDb([]).
insertNewNodesDb([[P,Ti,Lat,Long,Tf]|Tail]):-
    nodorosso(P,Ti,Lat,Long,Tf,Place),
    retract(nodorosso(P,Ti,Lat,Long,Tf,Place)),
    doppio(P,Ti,Lat,Long,Tf,Place,P2),
    add_rednode(P2,Ti,Lat,Long,Tf,Place),  % FUNZIONE PYTHON
    insertNewNodesDb(Tail),!.

% siccome su doppio elimina dei nodi senza toglierli dalla lista
% dobbiamo avere una "scappatoia" per quando si trova il nodo che non
% esiste più.
insertNewNodesDb([_|Tail]):-
    insertNewNodesDb(Tail).

% doppio vede se ci sono nuovi nodi rossi doppioni, fa la somma delle
% probabilità e li elimina senza inserirli più volte.
doppio(P,Ti,La,Lo,Tf,Place,P3):-
    nodorosso(P2,Ti,La2,Lo2,Tf,Place),
    close(La,Lo,La2,Lo2),
    retract(nodorosso(P2,Ti,_,_,Tf,Place)),
    Pnew is 1-((1-P)*(1-P2)).

%se il nodo non è doppione fa inserire la probabilità del nodo stesso
doppio(P,Ti,_,_,Tf,Place,P):-
    nodorosso(P2,Ti2,La2,Lo2,Tf2,Place),
    \+ Ti = Ti2.

