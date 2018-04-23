program ProjectMain;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, UnitTask, SysUtils;

var
	db           : TaskDB;
	criticalpath : LongInt;
	maxl         : LongInt;
	pcCount      : LongInt; 
begin
	try
		pcCount := getComputersCount(ParamStr(1));
		db := loadDBFromFile(ParamStr(1), pcCount);
		printDBContent(db);
		criticalpath := applyCPM(db);
		printDBContent(db);
		maxl := buildSchedule(db, criticalpath, pcCount);
		printDBContent(db);
		writeln();
		writeln('Critical Path: ', criticalpath);
		drawSchedule(db, maxl, 'Harmonogram.svg'); 
		drawGraph(db, 'Graf.svg');
		dropDB(db);
	except
		on EInOutError do
		writeln('File is not found or is corrupted.');
		on EAccessViolation do dropDB(db);
		on Exception do
		begin
			writeln('As we found cyclic dependencies in the tasks'' graph, we did not manage to count the critical path and to build a schedule.');
		end;
	end;
end.

// Author: Paul Lipkowski, University of Gdańsk
// Param 1 : Text file for a database with the information about the tasks, dependencies and the count of CPUs used
