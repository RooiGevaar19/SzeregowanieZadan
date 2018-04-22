program ProjectMain;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, UnitTask, SysUtils;

var
	db      : TaskDB;
	maxl    : LongInt;
	pcCount : LongInt; 
begin
	pcCount := getComputersCount(ParamStr(1));
	db := loadDBFromFile(ParamStr(1));
	printDBContent(db);
	maxl := applyCPM(db);
	printDBContent(db);
	buildSchedule(db, maxl, pcCount);
	printDBContent(db);
	dropDB(db);
end.

// Author: Paul Lipkowski, University of Gdańsk
// Param 1 : Text file for a database with the information about the tasks, dependencies and the count of CPUs used
