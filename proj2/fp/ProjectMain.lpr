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
		db := loadDBFromFile(ParamStr(1));
		if not (db.HasCycles) then
		begin
			drawGraph(db, 'Graf.svg');
			writeln('AFTER DATABASE LOAD:');
			printDBContent(db);
			//criticalpath := applyCPM(db);
			criticalpath := applyLiu(db);
			writeln();
			writeln('AFTER MODIFIED LIU ALGORITHM APPLICATION:');
			printDBContent(db);
			writeln();
			writeln('Latency:               ', db.Latency);
			writeln('Actual Execution Time: ', criticalpath);
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
