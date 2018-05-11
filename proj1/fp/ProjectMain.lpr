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
		if not (db.HasCycles) then
		begin
			writeln('AFTER DATABASE LOAD:');
			printDBContent(db);
			criticalpath := applyCPM(db);
			writeln();
			writeln('AFTER CPM APPLICATION:');
			printDBContent(db);
			writeln();
			writeln('AFTER SCHEDULE BUILD:');
			maxl := buildSchedule(db, criticalpath, pcCount);
			printDBContent(db);
			writeln();
			writeln('Critical Path Length:  ', criticalpath);
			writeln('Actual Execution Time: ', maxl);
			drawSchedule(db, maxl, 'Harmonogram.svg'); 
			drawGraph(db, 'Graf.svg');
		end;
		dropDB(db);
	except
		on EInOutError do
		writeln('File is not found or is corrupted.');
		on EAccessViolation do dropDB(db);
	end;
end.

// Author: Paul Lipkowski, University of Gdańsk
// Param 1 : Text file for a database with the information about the tasks, dependencies and the count of CPUs used
