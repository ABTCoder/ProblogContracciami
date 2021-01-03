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
%
:-dynamic nodorosso/6.
:-dynamic database/4.
:-dynamic nodo/2.

% predicato per cercare tutti gli individui che hanno dei nodi verdi nel
% database che matchano con dei nodi rossi. Vengono effettuate le somme
% e viene stampato l'indice di contagio per mandare l'avviso.
%
cercaAvvisi :-
    retractall(nodo(_,_)),
    findall(Prob,cercaDb(Prob),_),
    findall(Utente,nodo(Utente,_),Utenti),
    rimuovi_duplicati(Utenti,UtentiOk),
    scorriUtenti(UtentiOk).

% cerca tutti i nodi verdi che matchano con un nodo rosso attraverso
% l'ID_PLACE.
%
cercaDb(Prob):-
    db(Prob,T1,_,_,T2,Place),
    place(Utente,T3,_,_,T4,Place),
    valore(T1,T3,T2,T4,Prob,X),
    \+positivo(Utente,_),
    insNodo(Utente,X).
cercaDb(_).

% controlla se gli intervalli dei nodi trovati si sovrappongono, se sì
% restituisce il valore di PROB_CONT, se no, 0.
% DOVREMMO CONTROLLARE QUANTO TEMPO CI STA
%
valore(Ti1,Ti2,Tf1,Tf2,_,0):-
    Ti1>=Tf2,! ; Ti2>=Tf1,!.
valore(_,_,_,_,P,P).

% se il valore è nullo non fa niente, se ha un valore inserisce un nodo
% di appoggio.
%
insNodo(_,0):-!.
insNodo(Utente,Prob):-
    assert(nodo(Utente,Prob)).

% scorre tutti gli utenti che sono stati trovati con una probabilità di
% contagio non trascurabile, fa la somma delle PROB_CONT e stampa i
% risultati.
%
scorriUtenti([Utente|Utenti]):-
    cercaSomme(Utente,Somma),
    cf(Utente,CodFis),
    nl,write("L'indice di contagio di "),
    write(Utente),
    write(" è "),
    write(Somma),nl,
    write("Mandare l'avviso!! CodFiscale: "),
    write(CodFis),nl,
    scorriUtenti(Utenti),!.
scorriUtenti([Utente|Utenti]):-
    cercaSomme(Utente,Somma),
    nl,write("L'indice di contagio di "),
    write(Utente),
    write(" è "),
    write(Somma),nl,
    write("Mandare l'avviso!!"),
    write(" Questo utente non ha inserito il suo codice fiscale"),nl,
    scorriUtenti(Utenti),!.
scorriUtenti([]):- writeln("Fine processo!"),nl,nl.

% trova tutte le PROB_CONT di un utente e fa la somma.
% SICURAMENTE POSSIAMO FARE UN'ALTRA FUNZIONE PER SOMMA CON PROBLOG
%
cercaSomme(Utente,Somma):-
    findall(Prob,nodo(Utente,Prob),Lista),
    somma(Lista,Somma).

% inserimento di un individuo positivo
%
insPositivo:-
    % pulizia record di appoggio
    retractall(nodorosso(_,_,_,_,_,_)),
    retractall(database(_,_,_,_)),

    findall(_,scorriDb,_),

    write("Id dell'individuo risultato positivo al tampone"),nl,

    py_read(A),

    atom_string(A,Id),

    \+checkPos(Id),
    write("Data in cui è stato effettuato il tampone"),nl,
    writeln("Anno"),
    py_read_num(Y),nl,
    writeln("Mese"),
    py_read_num(M),nl,
    writeln("Giorno"),
    py_read_num(D),nl,
    writeln("Ora"),
    py_read_num(H),nl,
    writeln("Minuti"),
    py_read_num(Mn),nl,

    traduciData(Y,M,D,H,Mn,DataTampone),
    inserisciClausola('prolog/positivo.pl',positivo(Id,DataTampone)),

    findall([Ti,Tf,Place],place(Id,Ti,_,_,Tf,Place),ListaPlace),  % TUTTI I POSTI IN CUI è STATO IL POSITIVO

    syncPlace(DataTampone,ListaPlace),
    findall([Pnr,Tinr,Tfnr],nodorosso(Pnr,Tinr,_,_,Tfnr,_),Nodi),

    % salva tutti i nodi rossi sovrascrivendo il file db.pl
    open('prolog/db.pl',write,S),
    findall(_,inserisciDatabase(S),_),
    inserisciFile(Nodi,S),
    close(S),

    nl,write("Tutti i nodi verdi di "),
    write(Id),
    write(" sono stati trasformati e inseriti nel file db.pl!"),nl,

    checkCf(Id).

% salva tutti i nodi rossi nel database dinamico di appoggio.
%
scorriDb:-
    db(P,Ti,_,_,Tf,Pl),
    assert(database(P,Ti,Tf,Pl)).

% finchè esistono dei nodi verdi per quell'ID_INDIVIDUO continua a
% matchare con questo predicato.
% Trova la giusta PROB_CONT da associare a quel nodo e cerca se ci sono
% nodi rossi esistenti che si sovrappongono attraverso syncDB.
% Poi inserisce il nuovo nodo rosso e i nodi delle ore successive
% attraverso addSucc.
% Dt = Data tampone
%
syncPlace(_,[]):-!.
syncPlace(Dt,[[Ti,Tf,Place]|ListaPlace]):-
    c(Dt,Tf,P),                % ANCHE QUESTA FUNZIONE VA SICURAMENTE CAMBIATA
    checkP(P,X),               % X="ok" -> avanti; X="stop" -> prob trascurabile

    syncDb(X,P,Ti,Tf,Place),   % UN NODO VERDE ALLA VOLTA

    addSucc(X,P,Tf,Place),

    syncPlace(Dt,ListaPlace).

% per aggiungere i nodi rossi successivi al nodo verde preso dal file.
% 2 ore successive al tempo di fine con PROB_CONT decrescente del 30%
% ogni volta, fino a quando non diventa trascurabile -> "stop".
%
% ad ogni iterazione viene ricontrollato tutto il procedimento per
% controllare se si sovrappone ad un nodo già esistente.
%
addSucc("stop",_,_,_):-!.
addSucc("ok",P,Ti,Place):-
    Tf is Ti+7200000,
    Prob is P-0.3,
    checkP(Prob,X),
    syncDb(X,Prob,Ti,Tf,Place),
    addSucc(X,Prob,Tf,Place).

% richiama i predicati per sincronizzare i nodi rossi esistenti con il
% nodo verde preso in considerazione nel ciclo corrente
syncDb(X,P,Ti,Tf,Place):-
    joinList(X,Place,AllTempi,L),
    joinTime(P,Ti,Tf,Place,AllTempi),
    findall(Pr,nodorosso(Pr,_,_,_,_,Place),ListaNr),
    length(ListaNr,L2),
    nojoin(L,L2,P,Ti,Tf,Place).

% prende tutti i nodi vecchi e nuovi che hanno come place il luogo del
% nodo verde preso in considerazione e li inserisce in una lista per
% poterli scorrere tutti
% Se X="stop" restituisce la lista vuota così si procede con il
% successivo nodo verde
% POSSIAMO OTTIMIZZARLO PASSANDO I TEMPI
joinList("stop",_,[],"stop"):-!.
joinList("ok",Place,Tempi,L):-
    findall(["db",Tidb,Tfdb,Pdb],database(Pdb,Tidb,Tfdb,Place),TempiDb),
    findall(["nr",Tinr,Tfnr,Pnr],nodorosso(Pnr,Tinr,_,_,Tfnr,Place),TempiNr),
    length(TempiNr,L),
    append(TempiDb,TempiNr,Tempi).

% predicato ricorsivo, scorre tutti i nodi rossi vecchi e nuovi trovati
% e vede se i tempi coincidono con il nodo verde corrente.
% Si calcolano gli intervalli nel predicato t e vengono inseriti i nuovi
% nodi.
% P1 Ti Tf sono del nodo verde
joinTime(_,_,_,_,[]):-!.
joinTime(P1,Ti,Tf,Place,[[Tipo,Ti2,Tf2,P2]|AllTempi]):-
    ProbNew is P1+P2,
    p(ProbNew,P3),    % ARROTONDA A 0.99 SE MAGGIORE DI 1
    t(Place,Ti,Tf,Ti2,Tf2,P1,P2,P3,X),  %CREA 3 o 2 nodirossi\6
    deleteOld(X,Tipo,Ti2,Tf2,Place),
    joinTime(P1,Ti,Tf,Place,AllTempi).

% se si trova una corrispondenza nei tempi su joinTime e vengono
% inseriti altri nodi allora si elimina il nodo rosso che coincideva
% (può essere vecchio "db" oppure nuovo "nr")
% se non c'è nessuna corrispondenza ("no") non viene eliminato nessun
% nodo
%
deleteOld("no",_,_,_,_):-!.
deleteOld(_,"db",Ti,Tf,Place):-
    retract(database(_,Ti,Tf,Place)),!.
deleteOld(_,"nr",Ti,Tf,Place):-
    retract(nodorosso(_,Ti,_,_,Tf,Place)),!.
deleteOld(_,_,_,_,_):-!.

% quando sono stati scorsi tutti i nodi rossi vecchi e nuovi si
% considera il caso in cui nessuno di questi sia coincidente con il nodo
% che si sta inserendo, in quel caso s'inserisce il nodo verde.
% Si controlla questa coincidenza con la cardinalità di nodorosso prima
% e dopo di chiamare joinTime
% L2 LUNGHEZZA LISTA NODI ROSSI NUOVI DOPO joinTime
%
nojoin("stop",_,_,_,_,_):-!.
nojoin(L,L2,_,_,_,_):-
    L2>L,!.
nojoin(L,L,P,Ti,Tf,Place):-
    assert(nodorosso(P,Ti,_,_,Tf,Place)).

% inserimento dei nodi rossi vecchi nel file db.pl.
% S è lo stream che è stato aperto prima.
% Vengono inoltre filtrati dai nodi con più di 30 giorni dalla data
% corrente grazie a Tf>Limite.
%
inserisciDatabase(S):-
    database(P,Ti,Tf,Pl),
    % get_time(Curr),
    % Limite is (Curr-2592000)*1000,
    % Tf>Limite,
    portray_clause(S,db(P,Ti,_,_,Tf,Pl)).

% inserimento di tutti i nuovi nodi rossi nel database.
% Si scorre la lista di tutti i nodi che sono stati trovati, poi ogni
% volta che ne viene inserito uno nuovo viene anche eliminato dal
% database dinamico.
%
inserisciFile([],_).
inserisciFile([[P,Ti,Tf]|Tail],Stream):-
    nodorosso(P,Ti,Lat,Long,Tf,Place),
    retract(nodorosso(P,Ti,Lat,Long,Tf,Place)),
    doppio(P,Ti,Tf,Place,P2),
    portray_clause(Stream,db(P2,Ti,Lat,Long,Tf,Place)),
    inserisciFile(Tail,Stream),!.

% siccome su doppio elimina dei nodi senza toglierli dalla lista
% dobbiamo avere una "scappatoia" per quando si trova il nodo che non
% esiste più.
inserisciFile([_|Tail],S):-
    inserisciFile(Tail,S).

% doppio vede se ci sono nuovi nodi rossi doppioni, fa la somma delle
% probabilità e li elimina senza inserirli più volte.
doppio(P,Ti,Tf,Place,P3):-
    nodorosso(P2,Ti,_,_,Tf,Place),
    retract(nodorosso(P2,Ti,_,_,Tf,Place)),
    Pnew is P+P2,
    p(Pnew,P3).

%se il nodo non è doppione fa inserire la probabilità del nodo stesso
doppio(P,_,_,_,P).

