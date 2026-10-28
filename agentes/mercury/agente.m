%---------------------------------------------------------------------------%
% agente.m: agente de prueba en Mercury para el núcleo del juego.
%
% Habla con el núcleo por la entrada y la salida estándar, una línea de JSON
% por mensaje (contrato en pruebas_compartidas/protocolo/agente_*.json).
% Por cada `agente_turno` responde un `agente_plan`.
%
% Regla (la misma que agentes/python/agente.py; la prueba compara las dos):
%   - si el agravio de algún pop llega a 60, bajar el impuesto interno a 1;
%   - si no, y el tesoro baja de 5000, subirlo a 5;
%   - si no, dejarlo en 3, la tasa neutra.
%
% `decidir` es det: el compilador garantiza que siempre da exactamente un
% plan. Leer el JSON puede fallar (semidet); si una línea no es un turno
% válido, el agente no responde y la cáscara lo anota como tiempo agotado.
%
% Compilar:  mmc --make agente
%---------------------------------------------------------------------------%

:- module agente.
:- interface.
:- import_module io.

:- pred main(io::di, io::uo) is det.

%---------------------------------------------------------------------------%

:- implementation.

:- import_module bool.
:- import_module char.
:- import_module float.
:- import_module int.
:- import_module list.
:- import_module maybe.
:- import_module pair.
:- import_module string.

%---------------------------------------------------------------------------%
% El bucle: una línea, una respuesta.

main(!IO) :-
    io.read_line_as_string(Resultado, !IO),
    (
        Resultado = ok(Linea),
        ( if responder(Linea, Salida) then
            io.write_string(Salida, !IO),
            io.nl(!IO),
            io.flush_output(!IO)
        else
            true
        ),
        main(!IO)
    ;
        Resultado = eof
    ;
        Resultado = error(_)
    ).

:- pred responder(string::in, string::out) is semidet.

responder(Linea, Salida) :-
    valor(Turno, string.to_char_list(Linea), _),
    campo(Turno, "tipo", jstr("agente_turno")),
    campo(Turno, "tick", TickJ),
    numero_de(TickJ, TickF),
    campo(Turno, "entidades", jarr(Entidades)),
    list.foldl2(examinar, Entidades, 0.0, MaxAgravio, no, Tesoro),
    decidir(MaxAgravio, Tesoro, Tasa, Nota),
    Salida = string.format(
        "{\"tipo\":\"agente_plan\",\"tick\":%d,\"comandos\":[{\"tipo\":\"fijar_impuesto_interno\",\"valor\":%d}],\"nota\":\"%s\"}",
        [i(float.truncate_to_int(TickF)), i(Tasa), s(Nota)]).

%---------------------------------------------------------------------------%
% La regla.

:- pred decidir(float::in, maybe(float)::in, int::out, string::out) is det.

decidir(MaxAgravio, Tesoro, Tasa, Nota) :-
    ( if MaxAgravio >= 60.0 then
        Tasa = 1,
        Nota = string.format("agravio alto (%g)", [f(MaxAgravio)])
    else if Tesoro = yes(T), T < 5000.0 then
        Tasa = 5,
        Nota = string.format("tesoro bajo (%g)", [f(T)])
    else
        Tasa = 3,
        Nota = "equilibrio"
    ).

    % Mayor agravio entre las entidades que lo tienen, y el tesoro de la
    % facción si aparece.
    %
:- pred examinar(json::in, float::in, float::out,
    maybe(float)::in, maybe(float)::out) is det.

examinar(E, !MaxAgravio, !Tesoro) :-
    ( if
        campo(E, "magnitudes", Ms),
        campo(Ms, "agravio", A),
        campo(A, "efectivo", Ef),
        numero_de(Ef, F)
    then
        !:MaxAgravio = float.max(!.MaxAgravio, F)
    else
        true
    ),
    ( if
        campo(E, "ref", R),
        campo(R, "clase", jstr("faccion")),
        campo(E, "campos", Cs),
        campo(Cs, "tesoro", T),
        campo(T, "v", V),
        numero_de(V, TF)
    then
        !:Tesoro = yes(TF)
    else
        true
    ).

%---------------------------------------------------------------------------%
% Un lector de JSON mínimo: lo justo para leer un turno.

:- type json
    --->    jnull
    ;       jbool(bool)
    ;       jnum(float)
    ;       jstr(string)
    ;       jarr(list(json))
    ;       jobj(list(pair(string, json))).

:- pred campo(json::in, string::in, json::out) is semidet.

campo(jobj(Miembros), Clave, Valor) :-
    buscar(Miembros, Clave, Valor).

:- pred buscar(list(pair(string, json))::in, string::in, json::out) is semidet.

buscar([K - V | Resto], Clave, Valor) :-
    ( if K = Clave then
        Valor = V
    else
        buscar(Resto, Clave, Valor)
    ).

    % Los números del protocolo llegan como texto decimal exacto ("1.5") o
    % como número JSON.
    %
:- pred numero_de(json::in, float::out) is semidet.

numero_de(jnum(F), F).
numero_de(jstr(S), F) :-
    texto_a_float(S, F).

:- pred texto_a_float(string::in, float::out) is semidet.

texto_a_float(S, F) :-
    ( if string.to_int(S, I) then
        F = float.float(I)
    else
        string.to_float(S, F)
    ).

:- pred espacios(list(char)::in, list(char)::out) is det.

espacios(!Cs) :-
    ( if !.Cs = [C | Resto], char.is_whitespace(C) then
        !:Cs = Resto,
        espacios(!Cs)
    else
        true
    ).

:- pred valor(json::out, list(char)::in, list(char)::out) is semidet.

valor(V, !Cs) :-
    espacios(!Cs),
    !.Cs = [C | _],
    ( if C = '{' then
        objeto(V, !Cs)
    else if C = '[' then
        arreglo(V, !Cs)
    else if C = '"' then
        cadena(S, !Cs),
        V = jstr(S)
    else if !.Cs = ['t', 'r', 'u', 'e' | R1] then
        !:Cs = R1,
        V = jbool(yes)
    else if !.Cs = ['f', 'a', 'l', 's', 'e' | R2] then
        !:Cs = R2,
        V = jbool(no)
    else if !.Cs = ['n', 'u', 'l', 'l' | R3] then
        !:Cs = R3,
        V = jnull
    else
        numero(V, !Cs)
    ).

:- pred objeto(json::out, list(char)::in, list(char)::out) is semidet.

objeto(jobj(Miembros), !Cs) :-
    !.Cs = ['{' | R0],
    !:Cs = R0,
    espacios(!Cs),
    ( if !.Cs = ['}' | R1] then
        !:Cs = R1,
        Miembros = []
    else
        miembros(Miembros, !Cs),
        espacios(!Cs),
        !.Cs = ['}' | R2],
        !:Cs = R2
    ).

:- pred miembros(list(pair(string, json))::out,
    list(char)::in, list(char)::out) is semidet.

miembros([K - V | Resto], !Cs) :-
    espacios(!Cs),
    cadena(K, !Cs),
    espacios(!Cs),
    !.Cs = [':' | R0],
    !:Cs = R0,
    valor(V, !Cs),
    espacios(!Cs),
    ( if !.Cs = [',' | R1] then
        !:Cs = R1,
        miembros(Resto, !Cs)
    else
        Resto = []
    ).

:- pred arreglo(json::out, list(char)::in, list(char)::out) is semidet.

arreglo(jarr(Elementos), !Cs) :-
    !.Cs = ['[' | R0],
    !:Cs = R0,
    espacios(!Cs),
    ( if !.Cs = [']' | R1] then
        !:Cs = R1,
        Elementos = []
    else
        elementos(Elementos, !Cs),
        espacios(!Cs),
        !.Cs = [']' | R2],
        !:Cs = R2
    ).

:- pred elementos(list(json)::out, list(char)::in, list(char)::out) is semidet.

elementos([V | Resto], !Cs) :-
    valor(V, !Cs),
    espacios(!Cs),
    ( if !.Cs = [',' | R1] then
        !:Cs = R1,
        elementos(Resto, !Cs)
    else
        Resto = []
    ).

:- pred cadena(string::out, list(char)::in, list(char)::out) is semidet.

cadena(S, !Cs) :-
    !.Cs = ['"' | R0],
    !:Cs = R0,
    letras(Letras, !Cs),
    S = string.from_char_list(Letras).

:- pred letras(list(char)::out, list(char)::in, list(char)::out) is semidet.

letras(Letras, !Cs) :-
    !.Cs = [C | R0],
    !:Cs = R0,
    ( if C = '"' then
        Letras = []
    else if C = ('\\') then
        !.Cs = [E | R1],
        ( if E = 'u', R1 = [_, _, _, _ | R2] then
            % \uXXXX: el núcleo escribe UTF-8 directo, así que no aparece
            % en la práctica; se lee como '?'.
            !:Cs = R2,
            D = '?'
        else
            !:Cs = R1,
            escape(E, D)
        ),
        letras(Resto, !Cs),
        Letras = [D | Resto]
    else
        letras(Resto, !Cs),
        Letras = [C | Resto]
    ).

:- pred escape(char::in, char::out) is semidet.

escape('"', '"').
escape('\\', '\\').
escape('/', '/').
escape('n', '\n').
escape('t', '\t').
escape('r', '\r').
escape('b', '\b').
escape('f', '\f').

:- pred numero(json::out, list(char)::in, list(char)::out) is semidet.

numero(jnum(F), !Cs) :-
    list.take_while(es_de_numero, !.Cs, Cifras, Resto),
    Cifras = [_ | _],
    !:Cs = Resto,
    texto_a_float(string.from_char_list(Cifras), F).

:- pred es_de_numero(char::in) is semidet.

es_de_numero(C) :-
    ( char.is_digit(C)
    ; C = ('-')
    ; C = ('+')
    ; C = ('.')
    ; C = 'e'
    ; C = 'E'
    ).

%---------------------------------------------------------------------------%
:- end_module agente.
%---------------------------------------------------------------------------%
