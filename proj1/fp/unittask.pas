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
function applyCPM(var db : TaskDB) : LongInt; 
function buildSchedule(var db : TaskDB; maxl : LongInt; cpucount : LongInt) : LongInt;  
procedure drawSchedule(db : TaskDB; maxl : LongInt; filename : String); 
procedure drawGraph(db : TaskDB; filename : String);                       

implementation

uses
  Classes, SysUtils, Math;

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

function table_empty(tab : array of LongInt) : Boolean;
var
	i : LongInt;
	s : Boolean;
begin
	s := true;
	for i := 0 to Length(tab)-1 do
  		if (tab[i] <> -1) then s := false; 
  	table_empty := s;
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
	SetLength(pom.PrevTasks, 0);
	SetLength(pom.NextTasks, 0);
	pom.Visited := false;
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
end;

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

function getAllNextTasks(db : TaskDB; tk : Task) : TTasks;
var
	pom   : TTasks;
	i, j  : LongInt;
	tl    : Task;
begin
	SetLength(pom, Length(tk.NextTasks));
	j := 0;
	for i in tk.NextTasks do 
	begin
		tl := getTaskByID(db, i);
		pom[j] := tl;
		j := j + 1; 
	end;
	getAllNextTasks := pom;
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

function getAllPrevTasks(db : TaskDB; tk : Task) : TTasks;
var
	pom   : TTasks;
	i, j  : LongInt;
	tl    : Task;
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

function hasCycles(var db : TaskDB) : Boolean;
var
	queue    : array of Task;
	lcursor  : LongInt;
	rcursor  : LongInt;
	i, j, k  : LongInt;
	index    : LongInt;
	tk, tl   : Task;
	tks, tls : TTasks;
	answer   : Boolean;
begin 
	SetLength(queue, Length(db.Content));
	lcursor := 0;
	rcursor := 0;
	for i := 0 to Length(db.Content)-1 do 
		if Length(db.Content[i].PrevTasks) = 0 then 
		begin
			if (rcursor = Length(queue)) then SetLength(queue, rcursor+1);
			db.Content[i].Visited := true;
			queue[rcursor] := db.Content[i];
			Inc(rcursor);
		end;
	//write('Queue: '); for k := 0 to Length(queue)-1 do write(queue[k].id,' '); writeln();

	while (lcursor < rcursor) or (rcursor = Length(db.Content)-1) do
	begin
		//write('Queue: '); for k := 0 to Length(queue)-1 do write(queue[k].id,' '); writeln();
		//writeln(lcursor, ' ', rcursor);
		tk := queue[lcursor];
		Inc(lcursor);
		tks := getAllNextTasks(db, tk);
		//write('Next: '); for k := 0 to Length(tks)-1 do write(tks[k].id,' '); writeln();
		for tl in tks do
		begin
			if (table_allVisited(getAllPrevTasks(db, tl))) then
			begin
				index := getTaskDBAddress(db, tl.id);
				if (rcursor = Length(queue)) then SetLength(queue, rcursor+1);
				db.Content[index].Visited := true;
				queue[rcursor] := db.Content[index];
				Inc(rcursor);
			end;
		end;
	end;
	answer := not (allVisited(db)); 
	SetLength(queue, 0);
	hasCycles := answer;
end;

function loadDBFromFile(filename : String; cpucount : LongInt) : TaskDB;
var
	db : TaskDB;
begin
	db := setTasks(filename, cpucount);
	buildDependencies(db, filename);
	if (hasCycles(db)) then 
	begin
		writeln('ERROR: Graph contains cyclic dependencies!');
		db.HasCycles := true;
	end else begin
		db.HasCycles := false;
	end;
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

// ============ CPM and Schedule Building

function findCriticalPath(var db : TaskDB; var tk : Task) : LongInt; 
var
	i   : LongInt;
	pom : Task;
	tab : array of LongInt;
	s   : LongInt;
begin
	SetLength(tab, Length(tk.PrevTasks));
	for i := 0 to Length(tk.PrevTasks)-1 do
	begin
		pom := getTaskByID(db, tk.PrevTasks[i]);
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
		j := getTaskDBAddress(db, i);
		if Length(db.Content[j].PrevTasks) = 0 then 
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

function buildSchedule(var db : TaskDB; maxl : LongInt; cpucount : LongInt) : LongInt;  
var
	sched        : array of array of Integer;
	i, j         : LongInt;
	index, jndex : LongInt;
	assigned     : Boolean;
	cursor       : LongInt;
	usedcpus     : LongInt;
	s, xsize     : LongInt;
	expanded     : Boolean;
	maxs         : array of LongInt;
begin
	SetLength(sched, 0, 0);
	SetLength(maxs, Length(db.Content));
	xsize := maxl;
	expanded := false;
	if (cpucount <= 0) then // whether a count of CPUs is unbounded
	begin
		//writeln('lots of PCs');
		usedcpus := 1;
		SetLength(sched, usedcpus, maxl);
		for i := 0 to maxl-1 do 
			sched[usedcpus-1][i] := 0;
		//writeln('OK');

		//for tk in db.Content do 
		for index := 1 to Length(db.Content) do
		begin
			//writeln('OK   ', index);
			//writeln('CPUs ', usedcpus);
			jndex := getTaskDBAddress(db, index);
			//writeln('Index: ', jndex);
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
		//writeln('Done');
	end else begin // or is fixed
		SetLength(sched, cpucount, xsize);
		for i := 0 to cpucount-1 do 
			for j := 0 to maxl-1 do 
				sched[i][j] := 0;

		//for index := 1 to Length(db.Content) do
		for index in getAllIDs(db) do
		begin
			//writeln(index);
			jndex := getTaskDBAddress(db, index);
			assigned := false;
			cursor := db.Content[jndex].AvailabilityTime;
			repeat
				for i := 0 to cpucount-1 do 
					if (sched[i][cursor] <> 1) then
					begin
						if (cursor + db.Content[jndex].ExecutionTime + 1 > xsize) then 
						begin
							//write(xsize);
							xsize := cursor + db.Content[jndex].ExecutionTime + 1;
							SetLength(sched, cpucount, xsize);
							//writeln('expands to ', xsize);
							expanded := true;
						end;
						for j := 0 to db.Content[jndex].ExecutionTime-1 do sched[i][cursor+j] := 1;
						db.Content[jndex].CommenceTime := cursor;
						db.Content[jndex].AssignedMachine := i+1;
						assigned := true;
						break;
					end; 
				Inc(cursor);
				if (cursor = xsize) then break;
			until assigned;
		end;
	end;
	SetLength(sched, 0, 0);
	if expanded then xsize := xsize - 1; 
	buildSchedule := xsize;
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

