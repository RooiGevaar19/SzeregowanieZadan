unit UnitTask;

{$mode objfpc}{$H+}

interface

type
	Task = record 
	id               : LongInt;          // identyfikator
	ExecutionTime    : LongInt;          // czas wykonania
	AvailabilityTime : LongInt;          // minimalny czas dostępności (algorytm go uzupełni)
	CommenceTime     : LongInt;          // czas faktyczny wykonania (j.w.)
	AssignedMachine  : LongInt;          // przypisana maszyna (j.w.)
	PrecTasks        : array of LongInt; // wymagane taski
	NextTasks        : array of LongInt; // taski wychodzące
end;

type
	TaskDB = record
	Content : array of Task;
end;

function getTaskDBLocation(db : TaskDB; id : LongInt) : LongInt;  
function getTaskByID(db : TaskDB; id : LongInt) : Task;       
procedure replaceTaskByID(var db : TaskDB; newtask : Task);
function loadDBFromFile(filename : String) : TaskDB;
procedure printDBContent(db : TaskDB);
procedure dropDB(var db : TaskDB);
function findCriticalPath(var db : TaskDB; var tk : Task) : LongInt;        
function applyCPM(var db : TaskDB) : LongInt;                        

implementation

uses
  Classes, SysUtils;

// ========== Utils

function table_min(tab : array of LongInt) : LongInt;
var
	i : Integer;
	s : LongInt;
begin
	s := tab[0];
	for i := 1 to Length(tab)-1 do
		if (tab[i] < s) then s := tab[i];
	table_min := s;
end;

function table_max(tab : array of LongInt) : LongInt;
var
	i : Integer;
	s : LongInt;
begin
	s := tab[0];
	for i := 1 to Length(tab)-1 do
  		if (tab[i] > s) then s := tab[i]; 
  	table_max := s;
end;

// ========== DB Management

function buildTask(id, execution_time : LongInt) : Task;
var
	pom : Task;
begin
	pom.id := id;
	pom.ExecutionTime := execution_time;
	pom.AvailabilityTime := -1;
	pom.CommenceTime := -1;
	SetLength(pom.PrecTasks, 0);
	SetLength(pom.NextTasks, 0);
	buildTask := pom;
end;

procedure addDependency(var destination : Task; var origin : Task);
var 
	i, j : LongInt;
begin
	i := Length(destination.PrecTasks);
	j := Length(origin.NextTasks);
	SetLength(destination.PrecTasks, i+1);
	SetLength(origin.NextTasks, j+1);
	destination.PrecTasks[i] := origin.id;
	origin.NextTasks[i] := destination.id;
end;

function getTaskDBLocation(db : TaskDB; id : LongInt) : LongInt;
var
	found : Boolean;
	index : LongInt;
	i     : Task;
begin
	index := 0;
	found := false;
	for i in db.Content do
	begin
		if (i.id = id) then 
		begin
			found := true;
			break;
		end;
		Inc(index);
	end;
	if not (found) then getTaskDBLocation := -1
	else getTaskDBLocation := index;
end;

function getTaskByID(db : TaskDB; id : LongInt) : Task;
begin
	getTaskByID := db.Content[getTaskDBLocation(db, id)];
end;

procedure replaceTaskByID(var db : TaskDB; newtask : Task);
begin
	db.Content[getTaskDBLocation(db, newtask.id)] := newtask;
end;

function setTasks(filename : String) : TaskDB;
var
	db   : TaskDB;
	pom  : array of Task;
	fp   : Text;
	L    : TStrings;
	line : String;
	i    : Integer;
begin
	i := 0;
	SetLength(pom, i);
	assignfile(fp, filename);
    reset(fp);
    L := TStringlist.Create;
    L.Delimiter := ' ';
    L.StrictDelimiter := false;
    while not eof(fp) do
    begin
    	readln(fp, line);
    	L.DelimitedText := line;
    	if (L[0] = 'set') and (L[1] = 'task') and (L[3] = 'that') and (L[4] = 'lasts') then 
    	begin
    		SetLength(pom, i+1);
    		pom[i] := buildTask(StrToInt(L[2]), StrToInt(L[5]));
    		Inc(i);
    	end;
    end;
    L.Free;
    closefile(fp);
    db.Content := pom;
	SetLength(pom, 0);
	setTasks := db;
end;

procedure buildDependencies(var db : TaskDB; filename : String);
var
	fp          : Text;
	L           : TStrings;
	line        : String;
	destination : Task;
	origin      : Task;
begin
	assignfile(fp, filename);
    reset(fp);
    L := TStringlist.Create;
    L.Delimiter := ' ';
    L.StrictDelimiter := false;
    while not eof(fp) do
    begin
    	readln(fp, line);
    	L.DelimitedText := line;
    	if (L[0] = 'make') and (L[2] = 'dependent') and (L[3] = 'on') then 
    	begin
    		destination := getTaskByID(db, StrToInt(L[1]));
    		origin := getTaskByID(db, StrToInt(L[4]));
    		addDependency(destination, origin);
    		replaceTaskByID(db, destination);
    		replaceTaskByID(db, origin);
    	end;
    end;
    L.Free;
    closefile(fp);
end;


function loadDBFromFile(filename : String) : TaskDB;
var
	db : TaskDB;
begin
	db := setTasks(filename);
	buildDependencies(db, filename);
	loadDBFromFile := db;
end;

procedure printDBContent(db : TaskDB);
var
	dep, ava : String;
	tk       : Task;
	i        : LongInt;
begin
	for tk in db.Content do 
	begin
		if (Length(tk.PrecTasks) = 0) then 
		begin
			dep := ', is independent';
		end else begin
			dep := ', is dependent on [';
			for i in tk.PrecTasks do dep := dep + ' ' + IntToStr(i); 
			dep := dep + ' ]'
		end;
		if (tk.AvailabilityTime = -1) then 
		begin
			ava := '';
		end else begin
			if (tk.AvailabilityTime = 0) then ava := ' and begins immediately at best'
			//if (tk.AvailabilityTime = tk.ExecutionTime) then ava := ' and begins immediately at best'
			else ava := ' and begins at ' + IntToStr(tk.AvailabilityTime) + ' at best';
		end;
		writeln(StdErr, 'The task ', tk.id, ' lasts ', tk.ExecutionTime, dep, ava,'.');
	end;
end;

procedure dropDB(var db : TaskDB);
begin
	SetLength(db.Content, 0);
end;

// ============ CPM and Schedule Building

function findCriticalPath(var db : TaskDB; var tk : Task) : LongInt; 
var
	i   : LongInt;
	pom : Task;
	tab : array of LongInt;
	s   : LongInt;
begin
	SetLength(tab, Length(tk.PrecTasks));
	write('Task id ', tk.id, ' has [');
	for i := 0 to Length(tk.PrecTasks)-1 do
	begin
		pom := getTaskByID(db, tk.PrecTasks[i]);
		tab[i] := pom.ExecutionTime + pom.AvailabilityTime;
		write(' ', tab[i]);
	end; 
	s := table_max(tab);
	writeln(' ] and its max is ', s);
	SetLength(tab, 0);
	findCriticalPath := s;
end;

function applyCPM(var db : TaskDB) : LongInt;
var
	i, j : LongInt;
	tab  : array of LongInt; 
	maxs : array of LongInt;
begin
	SetLength(tab, Length(db.Content));
	SetLength(maxs, Length(db.Content));
	for i := 0 to Length(db.Content)-1 do tab[i] := db.Content[i].id;

	for i in tab do 
	begin
		j := getTaskDBLocation(db, i);
		if Length(db.Content[j].PrecTasks) = 0 then 
		begin
			//db.Content[j].AvailabilityTime := db.Content[j].ExecutionTime;
			db.Content[j].AvailabilityTime := 0;
			maxs[j] := db.Content[j].ExecutionTime; 
		end else begin
			db.Content[j].AvailabilityTime := findCriticalPath(db, db.Content[j]);
			maxs[j] := db.Content[j].ExecutionTime + db.Content[j].AvailabilityTime; 
		end;
	end;
	applyCPM := table_max(maxs);
end;

end.

