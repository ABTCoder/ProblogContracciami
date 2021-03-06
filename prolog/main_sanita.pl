% nodorosso è utilizzato per tenere traccia dei nuovi nodi rossi da
% inserire:
%    nodorosso(PROB_CONT,TIMEINIZIO,LAT,LONG,TIMEFINE,IDPLACE).
% database è utilizzato come database di appoggio dei nodi rossi che già
% esistevano per poter filtrarli e poterli reinserire nel database alla
% fine insieme ai nuovi nodi rossi:
%    database(PROB_CONT,TIMEINIZIO, LAT, LONG, TIMEFINE,IDPLACE).
%

:- use_module(library(assert)).
:- use_module('custom_predicates.py').
:- use_module(library(lists)).
:- use_module(library(cut)).
:- use_module(library(db)).
:- sqlite_load('app.db').

:- assertz(nodorosso/6).
:- assertz(database/6).

% controlla il tempo dalla data del tampone e restituisce la probabilità:
%   - entro 7 giorni dalla data del tampone -> alta
%   - dai 7 ai 14 giorni -> media
%   - dai 14 ai 20 giorni -> bassa
%   - oltre i 20 -> trascurabile
%   - il terzo argomento indica se il luogo è chiuso o aperto (1 = chiuso)
%     a seconda di ciò la probabilità assegnata varia leggermente
c(Dt,Tf,0,0.85):- Tf>=(Dt-(7*86400000)),  Tf=<(Dt+(7*86400000)). % 5 giorni
c(Dt,Tf,1,0.9):- Tf>=(Dt-(7*86400000)),  Tf=<(Dt+(7*86400000)). % 5 giorni

c(Dt,Tf,0,0.55):- Tf>=(Dt-(14*86400000)), Tf<(Dt-(7*86400000))  % da 5 a 10 giorni
             ; Tf>=(Dt+(7*86400000)),  Tf<(Dt+(14*86400000)).
c(Dt,Tf,1,0.6):- Tf>=(Dt-(14*86400000)), Tf<(Dt-(7*86400000)) % da 5 a 10 giorni
             ; Tf>=(Dt+(7*86400000)),  Tf<(Dt+(14*86400000)).
c(Dt,Tf,0,0.25):- Tf>=(Dt-(20*86400000)), Tf<(Dt-(14*86400000))  % da 10 a 15 giorni
             ; Tf>=(Dt+(14*86400000)), Tf<(Dt+(20*86400000)).
c(Dt,Tf,1,0.3):- Tf>=(Dt-(20*86400000)), Tf<(Dt-(14*86400000))  % da 10 a 15 giorni
             ; Tf>=(Dt+(14*86400000)), Tf<(Dt+(20*86400000)).
c(Dt,Tf,0,0.05):- Tf=<(Dt-(20*86400000))  % oltre 15 giorni
             ; Tf>=(Dt+(20*86400000)).
c(Dt,Tf,1,0.1):- Tf=<(Dt-(20*86400000))  % oltre 15 giorni
             ; Tf>=(Dt+(20*86400000)).



% controlla se la probabilità è trascurabile, in quel caso restituisce
% "stop" per dire di fermarsi.
%
checkP(Prob,stop):- Prob<0.2.
checkP(Prob,ok):- Prob>=0.2.

% crea i nuovi intervalli e li associa alle probabilità corrette
t(_,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2,_,_,_,no):-
    Ti1>=Tf2.               %non si sovrappongono
t(_,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2,_,_,_,no):-
    Ti2>=Tf1.
t(Place,Ti,La1,Lo1,Tf,Ti,La2,Lo2,Tf,_,_,P,si):-
    midpoint(La1,Lo1,La2,Lo2,La3,Lo3),
    assertz(nodorosso(P,Ti,La3,Lo3,Tf,Place)).    %sono completamente sovrapposti


% 4 casi di sovrapposizione senza avere tempi uguali.
t(Place,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2,P1,P2,P3,si):-
    Ti1<Ti2, Tf1>Ti2, Tf1<Tf2,
    midpoint(La1,Lo1,La2,Lo2,La3,Lo3),
    assertz(nodorosso(P1,Ti1,La1,Lo1,Ti2,Place)),
    assertz(nodorosso(P3,Ti2,La3,Lo3,Tf1,Place)),
    assertz(nodorosso(P2,Tf1,La2,Lo2,Tf2,Place)). %caso1
t(Place,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2,P1, _,P3,si):-
    Ti1<Ti2,Tf1>Tf2,
    midpoint(La1,Lo1,La2,Lo2,La3,Lo3),
    assertz(nodorosso(P1,Ti1,La1,Lo1,Ti2,Place)),
    assertz(nodorosso(P3,Ti2,La3,Lo3,Tf2,Place)),
    assertz(nodorosso(P1,Tf2,La1,Lo1,Tf1,Place)). %caso2

t(Place,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2, _,P2,P3,si):-
    Ti1>Ti2,Tf1<Tf2,
    midpoint(La1,Lo1,La2,Lo2,La3,Lo3),
    assertz(nodorosso(P2,Ti2,La2,Lo2,Ti1,Place)),
    assertz(nodorosso(P3,Ti1,La3,Lo3,Tf1,Place)),
    assertz(nodorosso(P2,Tf1,La2,Lo2,Tf2,Place)). %caso3

t(Place,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2,P1,P2,P3,si):-
    Ti1>Ti2,Tf1>Tf2, Ti1<Tf2,
    midpoint(La1,Lo1,La2,Lo2,La3,Lo3),
    assertz(nodorosso(P2,Ti2,La2,Lo2,Ti1,Place)),
    assertz(nodorosso(P3,Ti1,La3,Lo3,Tf2,Place)),
    assertz(nodorosso(P1,Tf2,La1,Lo1,Tf1,Place)). %caso4

% 4 casi di sovrapposizione dove ci sono tempi uguali.
t(Place,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2,_,P2,P3,si):-
    Ti1=Ti2,Tf1<Tf2,
    midpoint(La1,Lo1,La2,Lo2,La3,Lo3),
    assertz(nodorosso(P3,Ti2,La3,Lo3,Tf1,Place)),
    assertz(nodorosso(P2,Tf1,La2,Lo2,Tf2,Place)).  %caso1 e 3, ti1=ti2

t(Place,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2,P1, _,P3,si):-
    Ti1=Ti2,Tf1>Tf2,
    midpoint(La1,Lo1,La2,Lo2,La3,Lo3),
    assertz(nodorosso(P3,Ti2,La3,Lo3,Tf2,Place)),
    assertz(nodorosso(P1,Tf2,La1,Lo1,Tf1,Place)).  %caso2 e 4, ti1=ti2

t(Place,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2, _,P2,P3,si):-
    Tf1=Tf2,Ti1>Ti2,
    midpoint(La1,Lo1,La2,Lo2,La3,Lo3),
    assertz(nodorosso(P2,Ti2,La2,Lo2,Ti1,Place)),
    assertz(nodorosso(P3,Ti1,La3,Lo3,Tf1,Place)).  %caso3 e 4, Tf1=Tf2

t(Place,Ti1,La1,Lo1,Tf1,Ti2,La2,Lo2,Tf2,P1,_,P3,si):-
    Tf1=Tf2,Ti1<Ti2,
    midpoint(La1,Lo1,La2,Lo2,La3,Lo3),
    assertz(nodorosso(P1,Ti1,La1,Lo1,Ti2,Place)),
    assertz(nodorosso(P3,Ti2,La3,Lo3,Tf1,Place)).  %caso1 e 2, Tf1=Tf2


% inserimento di un individuo positivo
%   - Id: Id dell'utente
%   - Date: Data del tampone in millisecondi
%   - OldestMatch: Data del nodo rosso più vecchio con cui si è stati in contatto (0 se non ha avuto contatti)
%
insertPositive(Id, Date, OldestMatch):-

    % pulizia record di appoggio
    % Problog da errore se si esegue il retractall quando i record sono già vuoti
    % Quindi si aggiungono dei record temporanei
    assertz(nodorosso(0.5,1,1,1,1,"ff")),
    assertz(database(0.5,1,1,1,1,"ff")),
    retractall(nodorosso(_,_,_,_,_,_)),
    retractall(database(_,_,_,_,_,_)),

    % Problog restituisce errore se nel findall si usano variabili anonime _ ,quindi si mettono variabili casuali
    findall(A,scorriDb,A),

    % Tutti i posti in cui è stato il positivo esclusi quelli piu vecchi di OldestMatch
    findall([Ti,La,Lo,Tf,Place,Indoor],(place(Id,Ti,La,Lo,Tf,Place,Indoor),Tf>OldestMatch),ListaPlace),
    syncPlace(Date,ListaPlace),
    findall([Pnr,Tinr,Lanr,Lonr,Tfnr],nodorosso(Pnr,Tinr,Lanr,Lonr,Tfnr,_),Nodi),

    delete_old_nodes,  % Funzione Python, pulisce i vecchi nodi rossi
    % Aggiunge tutti i nodi rossi vecchi nel database
    findall(B,insertOldNodesDb,B),
    % Aggiunge tutti i nodi rossi nuovi nel database
    insertNewNodesDb(Nodi).

% salva tutti i vecchi nodi rossi nel database dinamico di appoggio.
%
scorriDb :-
    db(P,Ti,La,Lo,Tf,Pl),
    assertz(database(P,Ti,La,Lo,Tf,Pl)).

% finchè esistono dei nodi verdi per quell'ID_INDIVIDUO continua a
% matchare con questo predicato.
% Trova la giusta PROB_CONT da associare a quel nodo e cerca se ci sono
% nodi rossi esistenti che si sovrappongono attraverso syncDB.
% Poi inserisce il nuovo nodo rosso e i nodi delle ore successive
% attraverso addSucc.
% Dt = Data tampone
%
syncPlace(_,[]).
syncPlace(Dt,[[Ti,La,Lo,Tf,Place,Indoor]|ListaPlace]):-
    c(Dt,Tf,Indoor,P),
    checkP(P,X),               % X="ok" -> avanti; X="stop" -> prob trascurabile

    syncDb(X,P,Ti,La,Lo,Tf,Place),   % UN NODO VERDE ALLA VOLTA

    addSucc(X,P,Tf,La,Lo,Place,Indoor),
    syncPlace(Dt,ListaPlace).  % Chiamata ricorsiva

% per aggiungere i nodi rossi successivi al nodo verde preso dal database.
% 2 ore successive al tempo di fine con PROB_CONT decrescente del 30% per luoghi chiusi e del 40% per quelli aperti
% ogni volta, fino a quando non diventa trascurabile -> "stop".
%
% ad ogni iterazione viene ricontrollato tutto il procedimento per
% controllare se si sovrappone ad un nodo già esistente.
%
addSucc(stop,_,_,_,_,_,_).
addSucc(ok,P,Ti,La,Lo,Place,0):-
    Tf is Ti+7200000,
    Prob is P-0.4,
    checkP(Prob,X),
    syncDb(X,Prob,Ti,La,Lo,Tf,Place),
    addSucc(X,Prob,Tf,La,Lo,Place,0).
addSucc(ok,P,Ti,La,Lo,Place,1):-
    Tf is Ti+7200000,
    Prob is P-0.3,
    checkP(Prob,X),
    syncDb(X,Prob,Ti,La,Lo,Tf,Place),
    addSucc(X,Prob,Tf,La,Lo,Place,1).

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
% Se X=stop restituisce la lista vuota così si procede con il
% successivo nodo verde
% Prende solo i nodi con distanza in metri minore di 20m
joinList(stop,_,_,_,[],stop).
joinList(ok,Place,La,Lo,Tempi,L):-
    findall(["db",Tidb,Ladb,Lodb,Tfdb,Pdb],(database(Pdb,Tidb,Ladb,Lodb,Tfdb,Place), geo_distance(La,Lo,Ladb,Lodb,Dist1), Dist1 < 20 ),TempiDb),
    findall(["nr",Tinr,Lanr,Lonr,Tfnr,Pnr],(nodorosso(Pnr,Tinr,Lanr,Lonr,Tfnr,Place), geo_distance(La,Lo,Lanr,Lonr,Dist2), Dist2 < 20),TempiNr),
    length(TempiNr,L),
    append(TempiDb,TempiNr,Tempi).


% predicato ricorsivo, scorre tutti i nodi rossi vecchi e nuovi trovati
% e vede se i tempi coincidono con il nodo verde corrente.
% Si calcolano gli intervalli e le nuove coordinate nel predicato t e vengono inseriti i nuovi
% nodi.
% P1 Ti Tf sono del nodo verde
joinTime(_,_,_,_,_,_,[]).
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
deleteOld(no,_,_,_,_,_).
deleteOld(si,"db",Ti,Tf,Place,P):-
    retract(database(P,Ti,_,_,Tf,Place)).
deleteOld(si,"nr",Ti,Tf,Place,P):-
    retract(nodorosso(P,Ti,_,_,Tf,Place)).

% quando sono stati scorsi tutti i nodi rossi vecchi e nuovi si
% considera il caso in cui nessuno di questi sia coincidente con il nodo
% che si sta inserendo, in quel caso s'inserisce il nodo verde.
% Si controlla questa coincidenza con la cardinalità di nodorosso prima
% e dopo di chiamare joinTime
% L2 LUNGHEZZA LISTA NODI ROSSI NUOVI DOPO joinTime
%
nojoin(stop,_,_,_,_,_,_,_).
nojoin(L,L2,_,_,_,_,_,_):-
    \+ L = stop,
    L2>L.
nojoin(L,L,P,Ti,La,Lo,Tf,Place):-
    \+ L = stop,
    L2 = L,
    assertz(nodorosso(P,Ti,La,Lo,Tf,Place)).

% inserimento dei nodi rossi vecchi nel database.
insertOldNodesDb:-
    database(P,Ti,Lat,Long,Tf,Pl),
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
    insertNewNodesDb(Tail).

% Scappatoia per proseguire la ricorsione nel caso il predicato doppio abbia
% eliminato ulteriori nodi
insertNewNodesDb([[P,Ti,Lat,Long,Tf]|Tail]):-
    \+ nodorosso(P,Ti,Lat,Long,Tf,Place),
    insertNewNodesDb(Tail).

% doppio vede se ci sono nuovi nodi rossi doppioni, calcola la nuova
% probabilità e li elimina senza inserirli più volte.
doppio(P,Ti,La,Lo,Tf,Place,Pnew):-
    nodorosso(P2,Ti,La2,Lo2,Tf,Place),
    geo_distance(La,Lo,La2,Lo2,Dist),
    Dist < 20,
    retract(nodorosso(P2,Ti,_,_,Tf,Place)),
    Pnew is 1-((1-P)*(1-P2)).

%se il nodo non è doppione fa inserire la probabilità del nodo stesso
doppio(P,Ti,La,_,Tf,Place,P).



