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
		drawGraph(db, 'Graf.svg');
		if not (db.HasCycles) then
		begin
			writeln('AFTER DATABASE LOAD:');
			printDBContent(db);
			writeln();
			buildInTree(db);
			criticalpath := applyHu(db);
			writeln('AFTER HU APPLICATION:');
			printDBContent(db);
			writeln();
			writeln('Duration: ', criticalpath);
			drawSchedule(db, criticalpath, 'Harmonogram.svg'); 
		end;
		dropDB(db);
	except
		on EInOutError do
		writeln('File is not found or is corrupted.');
		//on EAccessViolation do dropDB(db);
	end;
end.

// Author: Paul Lipkowski, University of Gdańsk
// Param 1 : Text file for a database with the information about the tasks, dependencies and the count of CPUs used
