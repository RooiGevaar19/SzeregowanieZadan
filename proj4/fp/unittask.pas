unit UnitTask;

{$mode objfpc}{$H+}

interface

const SLESS = -1;
const SMORE = 1;
const TMAX = 2137;

type
	Task = record 
	id               : LongInt;          // identyfikator
	ExecutionTime    : LongInt;          // czas wykonania
	CommenceTime     : LongInt;          // czas faktyczny wykonania (j.w.)
	AssignedMachine  : LongInt;          // przypisana maszyna (j.w.)
end;

type
	TaskPair = record
	id          : LongInt;
	Task1       : Task;
	Task2       : Task;
	Task3       : Task;
	AssignedSet : LongInt;
	OrderValue  : LongInt;
end;

type TTasks     = array of Task;
type TTaskPairs = array of TaskPair;
type TLongInts  = array of LongInt;

type
	TaskDB = record
	Content : TTaskPairs;
end;


function loadDBFromFile(filename : String) : TaskDB;
procedure printDBContent(db : TaskDB);
procedure dropDB(var db : TaskDB);   
function applyJohnson(var db : TaskDB) : LongInt;
procedure drawSchedule(db : TaskDB; maxl : LongInt; filename : String);                

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

// ========== Task Management

function buildTask(id, ex1, cpu : LongInt) : Task;
var
	pom : Task;
begin
	pom.id := id;
	pom.ExecutionTime := ex1;
	pom.CommenceTime := -1;
	pom.AssignedMachine := cpu;
	buildTask := pom;
end;

function buildTaskPair(id : LongInt; tk1, tk2, tk3 : Task) : TaskPair;
var
	pom          : TaskPair;
	asset, order : LongInt;
begin
	if (tk1.ExecutionTime + tk2.ExecutionTime < tk2.ExecutionTime + tk3.ExecutionTime) then
	begin
		asset := SLESS;
		order := tk1.ExecutionTime + tk2.ExecutionTime;
	end else begin 
		asset := SMORE;
		order := tk2.ExecutionTime + tk3.ExecutionTime;
	end;
	pom.id := id;
	pom.Task1 := tk1;
	pom.Task2 := tk2;
	pom.Task3 := tk3;
	pom.AssignedSet := asset;
	pom.OrderValue := order;
	buildTaskPair := pom;
end;

function getSetOfTasks(db : TaskDB; const asset : LongInt) : TTaskPairs;
var
	pom : TTaskPairs;
	j   : LongInt;
	tl  : TaskPair;
begin
	j := 0;
	for tl in db.Content do 
	begin
		if tl.AssignedSet = asset then
		begin
			SetLength(pom, j+1);
			pom[j] := tl;
			Inc(j);
		end;
	end;
	getSetOfTasks := pom;
end;

// ========== DB Management

function getTaskDBAddress(db : TaskDB; id : LongInt) : LongInt;
var
	found : Boolean;
	index : LongInt;
	i     : TaskPair;
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

function getTaskByID(db : TaskDB; id : LongInt) : TaskPair;
begin
	getTaskByID := db.Content[getTaskDBAddress(db, id)];
end;

procedure replaceTaskPairByID(var db : TaskDB; newtask : TaskPair);
begin
	db.Content[getTaskDBAddress(db, newtask.id)] := newtask;
end;

function setTasks(filename : String) : TaskDB;
var
	db   : TaskDB;
	pom  : array of TaskPair;
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
    	if (L[0] = 'add') and (L[1] = 'task') and (L[3] = 'that') and (L[4] = 'lasts') and (L[6] = 'and') and (L[8] = 'and') then 
    	begin
    		SetLength(pom, i+1);
    		pom[i] := buildTaskPair(
    			      StrToInt(L[2]), 
    			      buildTask(StrToInt(L[2]), StrToInt(L[5]), 1), 
    			      buildTask(StrToInt(L[2]), StrToInt(L[7]), 2), 
    			      buildTask(StrToInt(L[2]), StrToInt(L[9]), 3)
    			);
    		Inc(i);
    	end;
    end;
    L.Free;
    closefile(fp);
    db.Content := pom;
	SetLength(pom, 0);
	setTasks := db;
end;

function loadDBFromFile(filename : String) : TaskDB;
var
	db : TaskDB;
begin
	db := setTasks(filename);
	loadDBFromFile := db;
end;

procedure printDBContent(db : TaskDB);
var
	tk : TaskPair;
begin
	for tk in db.Content do 
	begin
		writeln('The task ', tk.id,' has 2 subtasks that last ',tk.Task1.ExecutionTime,' and ',tk.Task2.ExecutionTime,' and ',tk.Task3.ExecutionTime,'.');
	end;
end;

procedure dropDB(var db : TaskDB);
begin
	SetLength(db.Content, 0);
end;

// ============ Johnson Algorithm

procedure sortAscending(var tab : TTaskPairs);
var
  i, j : Longint;
  pom  : TaskPair;
begin
  for j := Length(tab)-1 downto 1 do
    for i := 0 to j-1 do 
      if (tab[i].OrderValue > tab[i+1].OrderValue) then begin
        pom := tab[i];
        tab[i] := tab[i+1];
        tab[i+1] := pom;
      end;
end;

procedure sortDescending(var tab : TTaskPairs);
var
  i, j : Longint;
  pom  : TaskPair;
begin
  for j := Length(tab)-1 downto 1 do
    for i := 0 to j-1 do 
      if (tab[i].OrderValue < tab[i+1].OrderValue) then begin
        pom := tab[i];
        tab[i] := tab[i+1];
        tab[i+1] := pom;
      end;
end;

function JohnsonEngine(var db : TaskDB) : LongInt;
var
	lessSet, moreSet : TTaskPairs;
	matrix           : array of array of ShortInt;
	width            : LongInt;
	TimeCursor       : LongInt;
	index, jndex     : LongInt;
begin
	width := 0;
	setLength(matrix, 3, TMAX);
	lessSet := getSetOfTasks(db, SLESS);
	moreSet := getSetOfTasks(db, SMORE);
	sortAscending(lessSet);
	sortDescending(moreSet);
	width := 0;
	TimeCursor := 0;
	writeln('SET 1 OF TASKS');
	for index := 0 to Length(lessSet)-1 do 
	begin
		writeln('Task ', lessSet[index].id);
		// first task
		while (matrix[0][TimeCursor] = 1) do Inc(TimeCursor);
		lessSet[index].Task1.CommenceTime := TimeCursor;
		for jndex := 0 to lessSet[index].Task1.ExecutionTime-1 do matrix[0][TimeCursor+jndex] := 1;
		Inc(TimeCursor, lessSet[index].Task1.ExecutionTime);
		writeln('Subtask 1 starts at ', lessSet[index].Task1.CommenceTime, ' and lasts ', lessSet[index].Task1.ExecutionTime, '.');

		// second task
		while (matrix[1][TimeCursor] = 1) do Inc(TimeCursor);
		lessSet[index].Task2.CommenceTime := TimeCursor;
		for jndex := 0 to lessSet[index].Task2.ExecutionTime-1 do matrix[1][TimeCursor+jndex] := 1;
		Inc(TimeCursor, lessSet[index].Task2.ExecutionTime);
		writeln('Subtask 2 starts at ', lessSet[index].Task2.CommenceTime, ' and lasts ', lessSet[index].Task2.ExecutionTime, '.');

		// third task
		while (matrix[2][TimeCursor] = 1) do Inc(TimeCursor);
		lessSet[index].Task3.CommenceTime := TimeCursor;
		for jndex := 0 to lessSet[index].Task3.ExecutionTime-1 do matrix[2][TimeCursor+jndex] := 1;
		Inc(TimeCursor, lessSet[index].Task3.ExecutionTime);
		writeln('Subtask 3 starts at ', lessSet[index].Task3.CommenceTime, ' and lasts ', lessSet[index].Task3.ExecutionTime, '.');

		replaceTaskPairByID(db, lessSet[index]);
		width := TimeCursor;
		TimeCursor := lessSet[index].Task1.CommenceTime + lessSet[index].Task1.ExecutionTime;
	end;
	writeln();
	writeln('SET 2 OF TASKS');

	for index := 0 to Length(moreSet)-1 do 
	begin
		writeln('Task ', moreSet[index].id);
		// first task
		while (matrix[0][TimeCursor] = 1) do Inc(TimeCursor);
		moreSet[index].Task1.CommenceTime := TimeCursor;
		for jndex := 0 to moreSet[index].Task1.ExecutionTime-1 do matrix[0][TimeCursor+jndex] := 1;
		Inc(TimeCursor, moreSet[index].Task1.ExecutionTime);
		writeln('Subtask 1 starts at ', moreSet[index].Task1.CommenceTime, ' and lasts ', moreSet[index].Task1.ExecutionTime, '.');

		// second task
		while (matrix[1][TimeCursor] = 1) do Inc(TimeCursor);
		moreSet[index].Task2.CommenceTime := TimeCursor;
		for jndex := 0 to moreSet[index].Task2.ExecutionTime-1 do matrix[1][TimeCursor+jndex] := 1;
		Inc(TimeCursor, moreSet[index].Task2.ExecutionTime);
		writeln('Subtask 2 starts at ', moreSet[index].Task2.CommenceTime, ' and lasts ', moreSet[index].Task2.ExecutionTime, '.');

		// third task
		while (matrix[2][TimeCursor] = 1) do Inc(TimeCursor);
		moreSet[index].Task3.CommenceTime := TimeCursor;
		for jndex := 0 to moreSet[index].Task3.ExecutionTime-1 do matrix[2][TimeCursor+jndex] := 1;
		Inc(TimeCursor, moreSet[index].Task3.ExecutionTime);
		writeln('Subtask 3 starts at ', moreSet[index].Task3.CommenceTime, ' and lasts ', moreSet[index].Task3.ExecutionTime, '.');

		replaceTaskPairByID(db, moreSet[index]);
		width := TimeCursor;
		TimeCursor := moreSet[index].Task1.CommenceTime + moreSet[index].Task1.ExecutionTime;
	end;

	setLength(matrix, 0, 0);
	JohnsonEngine := width;
end;

function isDomination(db : TaskDB) : Boolean;
var
	flag : Boolean;
	tk   : TaskPair;
begin
	flag := true;
	for tk in db.Content do 
	begin
		if (tk.Task1.ExecutionTime < tk.Task2.ExecutionTime) or (tk.Task2.ExecutionTime > tk.Task3.ExecutionTime) then begin
			writeln('Task ',tk.id,' has subtasks with lengths of ',tk.Task1.ExecutionTime,' ',tk.Task2.ExecutionTime,' ',tk.Task3.ExecutionTime, 
				' and the subtask 2 is not dominated by other subtasks.');
			flag := false;
		end;
	end;
	isDomination := flag;
end;

function applyJohnson(var db : TaskDB) : LongInt;
begin
	if (isDomination(db)) then applyJohnson := JohnsonEngine(db)
	else raise exception.create('The middle tasks are not dominated by the outer tasks.') at get_caller_addr(get_frame), get_caller_frame(get_frame);   
end;

// ============ Utils

function getAllTasks(tab : TTaskPairs) : TTasks;
var
	pom            : TTasks;
	count          : LongInt;
	tl             : TaskPair;
begin
	count := 0;
	setLength(pom, count);
	for tl in tab do 
	begin
		setLength(pom, count+3);
		pom[count] := tl.Task1; 
		pom[count+1] := tl.Task2; 
		pom[count+2] := tl.Task3; 
		Inc(count, 3);
	end;
	getAllTasks := pom;
end;


procedure ScheduleEngine(tab : TTasks; maxl : LongInt; filename : String);   
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
	CPUCount := 3;
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
    for tk in tab do 
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

procedure drawSchedule(db : TaskDB; maxl : LongInt; filename : String);  
begin
	ScheduleEngine(getAllTasks(db.Content), maxl, filename);
end;

end.

