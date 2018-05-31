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
		writeln('AFTER DATABASE LOAD:');
		printDBContent(db);
		writeln();
		criticalpath := applyJohnson(db);
		writeln();
		writeln('Execution time:  ', criticalpath);
		drawSchedule(db, criticalpath, 'Harmonogram.svg'); 
		dropDB(db);
	except
		on EInOutError do writeln('ERROR: File is not found or is corrupted.');
		on EAccessViolation do begin
			writeln('ERROR: Access Violation.');
			dropDB(db);
		end;
		on E : Exception do begin
			if (E.Message = 'The middle tasks are not dominated by the outer tasks.') then writeln('ERROR: '+E.Message);
		end;
	end;
end.

// Author: Paul Lipkowski, University of Gdańsk
// Param 1 : Text file for a database with the information about the tasks, dependencies and the count of CPUs used
