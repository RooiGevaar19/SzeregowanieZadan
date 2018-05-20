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
	GraphPosX        : LongInt;
	GraphPosY        : LongInt;
	PrevTasks        : array of LongInt; // wymagane taski
	NextTasks        : array of LongInt; // taski wychodzące
	Visited          : Boolean;          // używane do sprawdzania cyklicznosci
	ReadyToGo        : LongInt;
	Level            : LongInt;
end;

type
	TaskDB = record
	Content       : array of Task;
	MachinesCount : LongInt;
	HasCycles     : Boolean;
end;

type TTasks    = array of Task;
type TLongInts = array of LongInt;

function loadDBFromFile(filename : String; cpucount : LongInt) : TaskDB;
function getComputersCount(filename : String) : LongInt;
procedure printDBContent(db : TaskDB);
procedure dropDB(var db : TaskDB);      
procedure buildInTree(var db : TaskDB);
function applyHu(var db : TaskDB) : LongInt;
procedure drawSchedule(db : TaskDB; maxl : LongInt; filename : String); 
procedure drawGraph(db : TaskDB; filename : String);                       

implementation

uses
  Classes, SysUtils, Math;

// ========== Utils

function table_min(tab : TLongInts) : LongInt;
var
	i : LongInt;
	s : LongInt;
begin
	s := tab[0];
	for i := 1 to Length(tab)-1 do
		if (tab[i] < s) then s := tab[i];
	table_min := s;
end;

function table_max(tab : TLongInts) : LongInt;
var
	i : LongInt;
	s : LongInt;
begin
	s := tab[0];
	for i := 1 to Length(tab)-1 do
  		if (tab[i] > s) then s := tab[i]; 
  	table_max := s;
end;

function table_empty(tab : TLongInts) : Boolean;
var
	i : LongInt;
	s : Boolean;
begin
	s := true;
	for i := 0 to Length(tab)-1 do
  		if (tab[i] <> -1) then s := false; 
  	table_empty := s;
end;

function min2(x, y : LongInt) : LongInt;
begin
	if (x < y) then min2 := x else min2 := y;
end;

function max2(x, y : LongInt) : LongInt;
begin
	if (x > y) then max2 := x else max2 := y;
end;

// ========== Task Management

procedure semaphoreDown(var tk : Task);
begin
	Inc(tk.ReadyToGo);
end;

procedure semaphoreUp(var tk : Task);
begin
	Dec(tk.ReadyToGo);
end;

function isSemaphoreOpen(tk : Task) : Boolean;
begin
	if tk.ReadyToGo = 0 then isSemaphoreOpen := true
	else isSemaphoreOpen := false;
end;

procedure table_unvisit(var db : TTasks);
var
	i : LongInt;
begin
	for i := 0 to Length(db)-1 do 
		db[i].Visited := false;
end;

function buildTask(id, execution_time : LongInt) : Task;
var
	pom : Task;
begin
	pom.id := id;
	pom.ExecutionTime := execution_time;
	pom.AvailabilityTime := -1;
	pom.CommenceTime := -1;
	pom.AssignedMachine := -2;
	pom.GraphPosX := -1;
	pom.GraphPosY := -1;
	SetLength(pom.PrevTasks, 0);
	SetLength(pom.NextTasks, 0);
	pom.Visited := false;
	pom.ReadyToGo := 0;
	pom.Level := 0;

	buildTask := pom;
end;

procedure addDependency(var destination : Task; var origin : Task);
var 
	i, j : LongInt;
begin
	i := Length(destination.PrevTasks);
	j := Length(origin.NextTasks);
	SetLength(destination.PrevTasks, i+1);
	SetLength(origin.NextTasks, j+1);
	destination.PrevTasks[i] := origin.id;
	origin.NextTasks[j] := destination.id;
	semaphoreDown(destination);
end;

// ========== DB Management

function getTaskDBAddress(db : TaskDB; id : LongInt) : LongInt;
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
	if not (found) then getTaskDBAddress := -1
	else getTaskDBAddress := index;
end;

function getTaskByID(db : TaskDB; id : LongInt) : Task;
begin
	getTaskByID := db.Content[getTaskDBAddress(db, id)];
end;

procedure replaceTaskByID(var db : TaskDB; newtask : Task);
begin
	db.Content[getTaskDBAddress(db, newtask.id)] := newtask;
end;

procedure appendNewTaskToDB(var db : TaskDB; tk : Task);
var
	x : LongInt;
begin
	x := Length(db.Content);
	SetLength(db.Content, x+1);
	db.Content[x] := tk;
end;

function getAvailableTasks(db : TaskDB) : TTasks;
var
	pom : TTasks;
	j   : LongInt;
	tl  : Task;
begin
	j := 0;
	for tl in db.Content do 
	begin
		if (isSemaphoreOpen(tl)) and (tl.Visited = false) then
		begin
			SetLength(pom, j+1);
			pom[j] := tl;
			Inc(j);
		end;
	end;
	getAvailableTasks := pom;
end;

function getAllPrevTasks(db : TaskDB; tk : Task) : TTasks;
var
	pom  : TTasks;
	i, j : LongInt;
	tl   : Task;
begin
	SetLength(pom, Length(tk.PrevTasks));
	j := 0;
	for i in tk.PrevTasks do 
	begin
		tl := getTaskByID(db, i);
		pom[j] := tl;
		j := j + 1; 
	end;
	getAllPrevTasks := pom;
end;

procedure releaseNextTasks(var db : TaskDB; tk : Task);
var
	i  : LongInt;
	tl : Task;
begin
	for i in tk.NextTasks do 
	begin
		tl := getTaskByID(db, i);
		semaphoreUp(tl); 
		replaceTaskByID(db, tl);
	end;
end;

function getAllNextTasks(db : TaskDB; tk : Task) : TTasks;
var
	pom   : TTasks;
	i, j  : LongInt;
	tl    : Task;
begin
	SetLength(pom, Length(tk.NextTasks));
	j := 0;
	for i in tk.PrevTasks do 
	begin
		tl := getTaskByID(db, i);
		pom[j] := tl;
		j := j + 1; 
	end;
	getAllNextTasks := pom;
end;

function getLeaves(db : TaskDB) : TTasks;
var
	pom : TTasks;
	j   : LongInt;
	tl  : Task;
begin
	j := 0;
	for tl in db.Content do 
	begin
		if Length(tl.NextTasks) = 0 then
		begin
			SetLength(pom, j+1);
			pom[j] := tl;
			Inc(j);
		end;
	end;
	getLeaves := pom;
end;

function setTasks(filename : String; cpucount : LongInt) : TaskDB;
var
	db   : TaskDB;
	pom  : array of Task;
	fp   : Text;
	L    : TStrings;
	line : String;
	i    : LongInt;
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
    	//if (L[0] = 'add') and (L[1] = 'task') and (L[3] = 'that') and (L[4] = 'lasts') then 
    	//begin
    	//	SetLength(pom, i+1);
    	//	pom[i] := buildTask(StrToInt(L[2]), StrToInt(L[5]));
    	//	Inc(i);
    	//end;
    	if (L[0] = 'add') and (L[1] = 'task') then 
    	begin
    		SetLength(pom, i+1);
    		pom[i] := buildTask(StrToInt(L[2]), 1);
    		Inc(i);
    	end;
    end;
    L.Free;
    closefile(fp);
    db.Content := pom;
    db.MachinesCount := cpucount;
	SetLength(pom, 0);
	setTasks := db;
end;

function getComputersCount(filename : String) : LongInt;
var
	fp   : Text;
	L    : TStrings;
	line : String;
	ct   : LongInt;
begin
	ct := 0;
	assignfile(fp, filename);
    reset(fp);
    L := TStringlist.Create;
    L.Delimiter := ' ';
    L.StrictDelimiter := false;
    while not eof(fp) do
    begin
    	readln(fp, line);
    	L.DelimitedText := line;
    	if (L[0] = 'use') and (L[1] = 'unlimited') and (L[2] = 'number') and (L[3] = 'of') and (L[4] = 'computers') then ct := 0;
    	if (L[0] = 'use') and (L[1] = '1') and (L[2] = 'computer') then ct := 1;
    	if (L[0] = 'use') and (L[2] = 'computers') then ct := StrToInt(L[1]);
    end;
    L.Free;
    closefile(fp);
	getComputersCount := ct;
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
    	if (L[0] = 'make') and (L[1] = 'task') and (L[3] = 'dependent') and (L[4] = 'on') and (L[5] = 'task') then 
    	begin
    		destination := getTaskByID(db, StrToInt(L[2]));
    		origin := getTaskByID(db, StrToInt(L[6]));
    		addDependency(destination, origin);
    		replaceTaskByID(db, destination);
    		replaceTaskByID(db, origin);
 			if (StrToInt(L[2]) < StrToInt(L[6])) then db.HasCycles := true;
    	end;
    end;
    L.Free;
    closefile(fp);
end;

function allVisited(db : TaskDB) : Boolean;
var
	tk : Task;
	s  : Boolean;
begin
	s := true;
	for tk in db.Content do 
		if not (tk.Visited) then s := false;
	allVisited := s;
end;

function table_allVisited(db : TTasks) : Boolean;
var
	tk : Task;
	s  : Boolean;
begin
	s := true;
	for tk in db do 
		if not (tk.Visited) then s := false;
	table_allVisited := s;
end;

function getAllIDs(db : TaskDB) : TLongInts;
var
	pom   : TLongInts;
	i     : Task;
	j     : LongInt;
begin
	SetLength(pom, Length(db.Content));
	j := 0;
	for i in db.Content do 
	begin
		pom[j] := i.id;
		j := j + 1; 
	end;
	getAllIDs := pom;
end;

function loadDBFromFile(filename : String; cpucount : LongInt) : TaskDB;
var
	db : TaskDB;
begin
	db := setTasks(filename, cpucount);
	db.HasCycles := false;
	buildDependencies(db, filename);
	loadDBFromFile := db;
end;

procedure printDBContent(db : TaskDB);
var
	dep, ava : String;
	com, ass : String;
	tk       : Task;
	i        : LongInt;
begin
	for tk in db.Content do 
	begin
		if (Length(tk.PrevTasks) = 0) then 
		begin
			dep := ', is independent';
		end else begin
			dep := ', is dependent on [';
			for i in tk.PrevTasks do dep := dep + ' ' + IntToStr(i); 
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
		if (tk.CommenceTime = -1) then
		begin
			com := '';
		end else begin
			com := ', but in fact it begins at '+IntToStr(tk.CommenceTime);
		end;
		if (tk.AssignedMachine = -2) then
		begin
			ass := '';
		end else begin
			ass := '. This task is assigned to a machine no. '+IntToStr(tk.AssignedMachine);
		end;
		writeln('The task ', tk.id, ' lasts ', tk.ExecutionTime, dep, ava, com, ass, '.');
	end;
end;

procedure dropDB(var db : TaskDB);
begin
	SetLength(db.Content, 0);
end;


//=========== Hu Algorithm

procedure setLevels(var db : TaskDB; id : LongInt; lv : LongInt);
var
	tl     : Task;
	addr   : LongInt; 
begin
	addr := getTaskDBAddress(db, id);
	db.Content[addr].Level := lv;
	for tl in getAllPrevTasks(db, db.Content[addr]) do setLevels(db, tl.id, lv+1);
end;

procedure buildInTree(var db : TaskDB);
var
	root   : Task;
	leaves : TTasks;
	i      : LongInt; 
begin
	root := buildTask(-1, 0);
	leaves := getLeaves(db);
	for i := 0 to Length(leaves)-1 do
	begin
		addDependency(root, leaves[i]);
		replaceTaskByID(db, leaves[i]);
	end;
	appendNewTaskToDB(db, root);

	setLevels(db, root.id, 0);
end;

procedure sortByLevel(var tab : TTasks);
var
  i, j : Longint;
  pom  : Task;
begin
  for j := Length(tab)-1 downto 1 do
    for i := 0 to j-1 do 
      if (tab[i].Level < tab[i+1].Level) then begin
        pom := tab[i];
        tab[i] := tab[i+1];
        tab[i+1] := pom;
      end;
end;

function applyHu(var db : TaskDB) : LongInt;
var
	TimeCursor       : LongInt;
	TaskEax, TaskEbx : LongInt;
	j, k             : LongInt;
	AvailableTasks   : TTasks;
	tk               : Task;
begin
	table_unvisit(db.Content);

	TimeCursor := 0;
	repeat
		AvailableTasks := getAvailableTasks(db);
		sortByLevel(AvailableTasks);
		//for tk in AvailableTasks do write(tk.id, ' ');
		//writeln;
		for j := 0 to min2(Length(AvailableTasks), db.MachinesCount)-1 do
		begin
			TaskEax := getTaskDBAddress(db, AvailableTasks[j].id);
			with db.Content[TaskEax] do 
			begin
				//writeln(id, ' ', TimeCursor);
				Visited := true;
				CommenceTime := TimeCursor;
				AssignedMachine := j+1;
				for k := 0 to Length(NextTasks)-1 do
				begin
					TaskEbx := getTaskDBAddress(db, NextTasks[k]);
					semaphoreUp(db.Content[TaskEbx]);
				end;
			end;
		end; 	
		Inc(TimeCursor);
	until table_allVisited(db.Content);

	applyHu := TimeCursor-1;
end;


//=========== Utils

procedure drawSchedule(db : TaskDB; maxl : LongInt; filename : String);   
var
	fp           : Text;
	schedSizeX   : LongInt; 
	schedSizeY   : LongInt;
	i            : LongInt;
	CPUCount     : LongInt;
	tk           : Task;
	TaskX, TaskY : LongInt;
	TaskLength   : LongInt;
begin
	CPUCount := db.MachinesCount;
	schedSizeX := maxl*100 + 200;
	schedSizeY := CPUCount*100 + 200;
	assignfile(fp, filename);
    rewrite(fp);
    writeln(fp, '<svg xmlns="http://www.w3.org/2000/svg" width="',schedSizeX,'" height="',schedSizeY,'" viewBox="0 0 ',schedSizeX,' ',schedSizeY,'">');
    writeln(fp, '<rect width="',schedSizeX,'" height="',schedSizeY,'" style="fill:rgb(255,255,255);stroke-width:0;stroke:rgb(0,0,0)" />');
    //writeln(fp, '<text x="20" y="50" font-family="Verdana" font-size="25" style="font-weight:bold">CPU</text>');
    writeln(fp, '<text x="10" y="',CPUCount*100+150,'" font-family="Verdana" font-size="25" style="font-weight:bold">Czas</text>');
    for i := 1 to CPUCount do 
    	writeln(fp, '<text x="10" y="',i*100+55,'" font-family="Verdana" font-size="20">CPU ',i,'</text>');
    for i := 0 to maxl do
    begin
    	writeln(fp, '<text x="',i*100+100,'" y="',CPUCount*100+150,'" font-family="Verdana" font-size="20">',i,'</text>');
    	writeln(fp, '<line x1="',i*100+100,'" y1="80" x2="',i*100+100,'" y2="',CPUCount*100+120,'" style="stroke:rgb(0,0,0);stroke-width:1" />');
    end;
    for tk in db.Content do 
    begin
    	TaskX := tk.CommenceTime*100+100;
    	TaskY := tk.AssignedMachine*100;
    	TaskLength := tk.ExecutionTime*100;
    	writeln(fp, '<rect x="',TaskX,'" y="',TaskY,'" width="',TaskLength,'" height="100" style="fill:rgb(128,128,255);stroke-width:2;stroke:rgb(0,0,0)" />');
    	writeln(fp, '<text x="',TaskX+10,'" y="',TaskY+60,'" font-family="Verdana" font-size="18" fill="white">Task ',tk.id,'</text>');
    end; 
    writeln(fp, '</svg>');
    closefile(fp);
	writeln('A schedule image has been generated to the file "', filename, '".');
end;

procedure drawGraph(db : TaskDB; filename : String); 
var
	fp           : Text;
	schedSizeX   : LongInt; 
	schedSizeY   : LongInt;
	i            : LongInt;
	MiddleX      : LongInt;
	MiddleY      : LongInt;
	tk, tl       : Task;
	TaskX, TaskY : LongInt;
	atan         : Extended;
	angle        : LongInt;
	posX, posY   : LongInt;
begin
	schedSizeX := 1000;
	schedSizeY := 1000;
	MiddleX := schedSizeX div 2;
	MiddleY := schedSizeY div 2;

	for i := 0 to Length(db.Content)-1 do
	begin
		db.Content[i].GraphPosX := MiddleX - trunc((MiddleX-150)*(cos(i/(Length(db.Content)) *2*pi()+0.01)));
		db.Content[i].GraphPosY := MiddleY - trunc((MiddleY-150)*(sin(i/(Length(db.Content)) *2*pi()+0.01)));
	end;

	assignfile(fp, filename);
    rewrite(fp);
    writeln(fp, '<svg xmlns="http://www.w3.org/2000/svg" width="',schedSizeX,'" height="',schedSizeY,'" viewBox="0 0 ',schedSizeX,' ',schedSizeY,'">');
    writeln(fp, '<rect width="',schedSizeX,'" height="',schedSizeY,'" style="fill:rgb(255,255,255);stroke-width:0;stroke:rgb(0,0,0)" />');

    for tk in db.Content do 
    begin
    	for i := 0 to Length(tk.PrevTasks)-1 do 
    	begin
    		tl := getTaskByID(db, tk.PrevTasks[i]);
    		atan := (1.0 * tk.GraphPosX - tl.GraphPosX)/(1.0 * tk.GraphPosY - tl.GraphPosY);
    		angle := trunc(radtodeg(arctan(atan))) - 90;
    		if (angle < 0) then angle := 360 - angle;
    		writeln(fp, '<line x1="',tk.GraphPosX,'" y1="',tk.GraphPosY,'" x2="',tl.GraphPosX,'" y2="',tl.GraphPosY,'" style="stroke:rgb(0,0,0);stroke-width:2" />');
    		if (tk.GraphPosY < tl.GraphPosY) then
    			writeln(fp, '<polygon points="2,7 0,0 11,7 0,14" transform="translate(',tk.GraphPosX+trunc(50*cos(degtorad(angle))),' ',tk.GraphPosY+trunc(50*sin(degtorad(angle))),') rotate(',angle+180,' 0 0) translate(-2 -7)" stroke="black" fill="black" />')
    		else
    			writeln(fp, '<polygon points="2,7 0,0 11,7 0,14" transform="translate(',tk.GraphPosX-trunc(50*cos(degtorad(angle))),' ',tk.GraphPosY-trunc(50*sin(degtorad(angle))),') rotate(',angle,' 0 0) translate(-2 -7)" stroke="black" fill="black" />');
    
    	end;
    end; 

    for i := 0 to Length(db.Content)-1 do 
    begin
    	tk := db.Content[i];
    	if (i*4 < (Length(db.Content))) or (i*4.0/3 > (Length(db.Content))) then posX := tk.GraphPosX-130
    	else posX := tk.GraphPosX+30;
    	if (i*2 < (Length(db.Content))) then posY := tk.GraphPosY-50
    	else posY := tk.GraphPosY+60;
    	writeln(fp, '<circle cx="',tk.GraphPosX,'" cy="',tk.GraphPosY,'" r="40" stroke="black" stroke-width="3" fill="#008844" />');
    	writeln(fp, '<text x="',posX,'" y="',posY,'" font-family="Verdana" font-size="24" fill="black">Task ',tk.id,'</text>');
    	writeln(fp, '<text x="',tk.GraphPosX-10,'" y="',tk.GraphPosY+10,'" font-family="Verdana" font-size="24" fill="white">',tk.ExecutionTime,'</text>');
    end; 
    writeln(fp, '</svg>');
    closefile(fp);
	writeln('A graph image has been generated to the file "', filename, '".');
end;

end.

