unit UnitTask;

{$mode objfpc}{$H+}

interface

const
	GraphImageSizeX = 1000;
	GraphImageSizeY = 1000;

type
	Task = record 
	id               : LongInt;          // identyfikator
	ExecutionTime    : LongInt;          // czas wykonania
	AvailabilityTime : LongInt;          // minimalny czas dostępności (algorytm go uzupełni)
	CommenceTime     : LongInt;          // czas faktyczny wykonania (j.w.)
	AssignedMachine  : LongInt;          // przypisana maszyna (j.w.)
	GraphPosX        : LongInt;
	GraphPosY        : LongInt;
	PrecTasks        : array of LongInt; // wymagane taski
	NextTasks        : array of LongInt; // taski wychodzące
end;

type
	TaskDB = record
	Content            : array of Task;
	MachinesCount      : LongInt;
end;

function getTaskDBLocation(db : TaskDB; id : LongInt) : LongInt;  
function getTaskByID(db : TaskDB; id : LongInt) : Task;       
procedure replaceTaskByID(var db : TaskDB; newtask : Task);
function loadDBFromFile(filename : String; cpucount : LongInt) : TaskDB;
function getComputersCount(filename : String) : LongInt;
procedure printDBContent(db : TaskDB);
procedure dropDB(var db : TaskDB);
function findCriticalPath(var db : TaskDB; var tk : Task) : LongInt;        
function applyCPM(var db : TaskDB) : LongInt; 
procedure buildSchedule(var db : TaskDB; maxl : LongInt; cpucount : LongInt);
procedure drawSchedule(db : TaskDB; maxl : LongInt; filename : String);                       

implementation

uses
  Classes, SysUtils;

// ========== Utils

function table_min(tab : array of LongInt) : LongInt;
var
	i : LongInt;
	s : LongInt;
begin
	s := tab[0];
	for i := 1 to Length(tab)-1 do
		if (tab[i] < s) then s := tab[i];
	table_min := s;
end;

function table_max(tab : array of LongInt) : LongInt;
var
	i : LongInt;
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
	pom.AssignedMachine := -2;
	pom.GraphPosX := -1;
	pom.GraphPosY := -1;
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
    	if (L[0] = 'add') and (L[1] = 'task') and (L[3] = 'that') and (L[4] = 'lasts') then 
    	begin
    		SetLength(pom, i+1);
    		pom[i] := buildTask(StrToInt(L[2]), StrToInt(L[5]));
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
	i    : LongInt;
	ct   : LongInt;
begin
	i := 0;
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
    	end;
    end;
    L.Free;
    closefile(fp);
end;


function loadDBFromFile(filename : String; cpucount : LongInt) : TaskDB;
var
	db : TaskDB;
begin
	db := setTasks(filename, cpucount);
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

// ============ CPM and Schedule Building

function findCriticalPath(var db : TaskDB; var tk : Task) : LongInt; 
var
	i   : LongInt;
	pom : Task;
	tab : array of LongInt;
	s   : LongInt;
begin
	SetLength(tab, Length(tk.PrecTasks));
	for i := 0 to Length(tk.PrecTasks)-1 do
	begin
		pom := getTaskByID(db, tk.PrecTasks[i]);
		tab[i] := pom.ExecutionTime + pom.AvailabilityTime;
	end; 
	s := table_max(tab);
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
			db.Content[j].AvailabilityTime := 0;
			maxs[j] := db.Content[j].ExecutionTime; 
		end else begin
			db.Content[j].AvailabilityTime := findCriticalPath(db, db.Content[j]);
			maxs[j] := db.Content[j].ExecutionTime + db.Content[j].AvailabilityTime; 
		end;
	end;
	applyCPM := table_max(maxs);
end;

// ========== Schedule Generation

procedure buildSchedule(var db : TaskDB; maxl : LongInt; cpucount : LongInt);  
var
	sched        : array of array of Integer;
	i, j         : LongInt;
	index, jndex : LongInt;
	assigned     : Boolean;
	cursor       : LongInt;
	usedcpus     : LongInt;
begin
	SetLength(sched, 0, 0);
	if (cpucount <= 0) then // whether a count of CPUs is unbounded
	begin
		usedcpus := 1;
		SetLength(sched, usedcpus, maxl);
		for i := 0 to maxl-1 do 
			sched[usedcpus-1][i] := 0;

		//for tk in db.Content do 
		for index := 0 to Length(db.Content) do
		begin
			jndex := getTaskDBLocation(db, index);
			assigned := false;
			cursor := db.Content[jndex].AvailabilityTime;
			for i := 0 to usedcpus-1 do 
				if (sched[i][cursor] = 0) then
				begin
					for j := 0 to db.Content[jndex].ExecutionTime-1 do sched[i][cursor+j] := 1;
					db.Content[jndex].CommenceTime := cursor;
					db.Content[jndex].AssignedMachine := i+1;
					assigned := true;
					break;
				end; 
			if not assigned then
			begin
				Inc(usedcpus);
				SetLength(sched, usedcpus, maxl);
				for i := 0 to maxl-1 do 
					sched[usedcpus-1][i] := 0;

				for j := 0 to db.Content[jndex].ExecutionTime-1 do sched[usedcpus-1][cursor+j] := 1;
				db.Content[jndex].CommenceTime := cursor;
				db.Content[jndex].AssignedMachine := usedcpus;
				assigned := true;
			end;
		end;
		db.MachinesCount := usedcpus;
	end else begin // or is fixed
		SetLength(sched, cpucount, maxl);
		for i := 0 to cpucount-1 do 
			for j := 0 to maxl-1 do 
				sched[i][j] := 0;

		for index := 0 to Length(db.Content) do
		begin
			jndex := getTaskDBLocation(db, index);
			assigned := false;
			cursor := db.Content[jndex].AvailabilityTime;
			repeat
				for i := 0 to cpucount-1 do 
					if (sched[i][cursor] = 0) then
					begin
						for j := 0 to db.Content[jndex].ExecutionTime-1 do sched[i][cursor+j] := 1;
						db.Content[jndex].CommenceTime := cursor;
						db.Content[jndex].AssignedMachine := i+1;
						assigned := true;
						break;
					end; 
				Inc(cursor);
				if (cursor = maxl) then break;
			until assigned;
		end;
	end;
	SetLength(sched, 0, 0);
end;

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
    writeln(fp, '<text x="20" y="50" font-family="Verdana" font-size="25" style="font-weight:bold">CPU</text>');
    writeln(fp, '<text x="10" y="',CPUCount*100+150,'" font-family="Verdana" font-size="25" style="font-weight:bold">Czas</text>');
    for i := 1 to CPUCount do 
    	writeln(fp, '<text x="40" y="',i*100+50,'" font-family="Verdana" font-size="25">',i,'</text>');
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
	writeln('A schedule image generated as the file ', filename, '');
end;

end.

