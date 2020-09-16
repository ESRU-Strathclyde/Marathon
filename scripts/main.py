#! /usr/bin/env python3

# ESRU 2018

# This is the back end simulation service for the Marathon service. Once
# invoked, this program will run in an infinite loop until a fatal error
# occurs or the process is terminated. Simulation jobs, requested by the
# Marathon front end, will be spawned as seperate processes in parallel.
# The process of checking jobs is termed a dispatch, and happens at 
# intervals determined by a command line argument. Communication between 
# the front and back ends is accomplished by an SQL database and a shared 
# directory tree, see documentation for details.

# Command line options:
# -h, --help  - displays help text
# -d, --debug - service prints debug information to standard out,
#               and jobs print debug information to "[jobID].log"
#               in the job folder (../jobs/job_[jobID]).

# Command line arguments:
# 1: path to shared folder
# 2: [optional] dispatch interval in seconds

import sys
from os.path import isfile,isdir,realpath,dirname,basename
from os import devnull,makedirs,chdir,kill,remove,rename
from subprocess import run,Popen,PIPE,STDOUT
from time import sleep,time
from multiprocessing import Process,Pipe
import re
from datetime import datetime
from shutil import copytree,copyfile,rmtree,move
from glob import glob
import signal
from mysql import connector
import ctypes
from setproctitle import setproctitle

### FUNCTION: runJob
# This runs a performance assessment on an ESP-r model. This should be run in a
# seperate process, otherwise errors will terminate the main script. If
# debugging is active, a log file will be written out to "[jobID].log". If the
# job fails due to an error, a file called "[jobID.err]" will be written out
# containing the error message.

def runFakeJob(s_jobID): 
    
    setproctitle('marathon'+s_jobID)

    s_jobDir=getJobDir(s_jobID)
    if isdir(s_jobDir):
        rmtree(s_jobDir)
    makedirs(s_jobDir)
    chdir(s_jobDir)

    while True:
        sleep(10)

def runJob(s_jobID,s_tarball,s_MD5,s_building,s_estate,s_estateType,s_asmtName,ts_criteria,b_debug,con,s_shareDir):

    setproctitle('marathon'+s_jobID)

    s_jobDir=getJobDir(s_jobID)
    if isdir(s_jobDir):
        rmtree(s_jobDir)
    makedirs(s_jobDir)
    chdir(s_jobDir)

    # Create a directory for the outputs.
    makedirs('outputs')

    # Create temporary directory.
    makedirs('tmp')

    if b_debug:
        f_log=open(s_jobID+'.log','w')
        curDateTime=datetime.now()
        s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
        f_log.write('*** JOB STARTED @ '+s_dateTime+' ***\nJobID: '+s_jobID+'\n')
    else:
        f_log=None

    ### FUNCTION: SIGTERMhandler
    # Terminate signal handler, calls jobError to ensure error output
    # is generated and uploaded.
    def SIGTERMhandler(signal,frame):
        jobError(s_jobID,'job recieved a terminate signal',15,b_debug,f_log,s_shareDir)

    signal.signal(signal.SIGTERM,SIGTERMhandler)

    # Send started signal.
    i_prgv=1
    con.send(i_prgv)

    # Model file path and extension.
    s_modelFile=s_shareDir+'/Models/'+s_tarball
    s_ext=s_tarball.split('.',1)[1]

    # Get model.
    if b_debug: f_log.write('Retrieving model file '+s_modelFile+'\n')

    # # If there is an MD5 checksum passed from the front end, get checksum of the model file and compare them.
    # # Wait up to 100 seconds for model to appear and checksums to match.  
    # if not s_MD5sum is None:
    #     if b_debug: f_log.write('Checking MD5 checksum ...\n')  
    #     if b_debug: f_log.write('Checksum from front end: '+s_MD5sum+'\n')
    #     s_MD5sum=s_MD5sum.strip()
    #     i_count=0
    #     s_modelMD5=''
    #     while True:
    #         try:
    #             s_modelMD5=run(['md5sum',s_modelFile],check=True,sdtout=PIPE,text=True).stdout.split()[0]
    #         except:
    #             pass            
    #         if b_debug:f_log.write('Local checksum: '+s_modelMD5+'\n')
    #         if s_modelMD5==s_MD5sum: break
    #         i_count+=1
    #         if i_count>10:            
    #             # Timeout.
    #             jobError(s_jobID,'Timeout while waiting for model file "'+s_model+'"',11,b_debug,f_log,s_shareDir)
    #         if b_debug: f_log.write('Checksum does not match, waiting ...\n')
    #         sleep(10)
    #     if b_debug: f_log.write('Checksum verified.\n')
    # else:
    #     if b_debug: f_log.write('MD5 checksum not found.\n')

    # Now get the model.
    try:
        copyfile(s_modelFile,'./'+s_tarball)
    except:
        # Error - cannot find model.
        jobError(s_jobID,'error retrieving model "'+s_tarball+'"',11,b_debug,f_log,s_shareDir)
    else:
        if s_ext=='zip':
            ls_extract=['unzip']
        elif s_ext=='tar' or s_ext=='tar.gz':
            ls_extract=['tar','-xf']
        elif s_ext=='xml':
            ls_extract=['../../scripts/common/gbXMLconv/gbXMLconv.sh']
        else:
            jobError(s_jobID,'unrecognised model archive format (.zip, .tar, .tar.gz and .xml (gbXML) supported)',16,b_debug,f_log,s_shareDir)
        try:
            run(ls_extract+[s_tarball],check=True)
            remove(s_tarball)
        except:
            jobError(s_jobID,'failed to extract model',16,b_debug,f_log,s_shareDir)
        
    # Move model into folder called "model".
    ls_dirs=[a for a in glob('./*') if not a=='./tmp' and not a=='./outputs' and isdir(a)]
    makedirs('model')
    if len(ls_dirs)==1:
    # One directory found, probably means the model directories are inside this.
        try:
            run(['mv','-t','model']+glob('./'+ls_dirs[0]+'/*'),check=True)
        except:
            jobError(s_jobID,'failed to extract model',16,b_debug,f_log,s_shareDir)
        rmtree(ls_dirs[0])
    else:
        try:
            run(['mv','-t','model']+ls_dirs,check=True)  
        except:
            jobError(s_jobID,'failed to extract model',16,b_debug,f_log,s_shareDir)

    # Find cfg file. Must be only one in the cfg directory.
    ls_cfg=glob('model/cfg/*.cfg')
    if len(ls_cfg)==0:
        jobError(s_jobID,'cfg file not found in model cfg directory',13,b_debug,f_log,s_shareDir)
    elif len(ls_cfg)>1:
        jobError(s_jobID,'more than one cfg file found in model cfg directory',14,b_debug,f_log,s_shareDir)
    s_cfg=ls_cfg[0]
    if b_debug: f_log.write('Building: '+s_building+'\nModel: '+s_modelFile+'\ncfg file: '+s_cfg+'\n\n')
    s_cfgdir=dirname(s_cfg)

    # Write preamble.
    s_time=curDateTime.strftime('%H:%M')
    s_date=curDateTime.strftime('%d/%m/%y')
    # if s_PAM=='ISO7730_thermal_comfort':
    #     s_PAMpreStr='BS EN ISO 7730 (2005)\\footnote{BS (2005) BS EN ISO 7730 Ergonomics of the thermal environment - Analytical determination and interpretation of thermal comfort using calculation of the PMV and PPD indices and local thermal comfort criteria. London: British Standards Institute.} thermal comfort'
    # elif s_PAM=='visual_comfort':
    #     s_PAMpreStr='BS EN 12464-1 (2011)\\footnote{BS (2011) BS EN 12464-1 Light and lighting - Lighting of work places, Part 1: Indoor work places. London: British Standards Institute.} visual comfort'
    # elif s_PAM=='indoor_air_quality':
    #     s_PAMpreStr='BS EN 15251 (2007)\\footnote{BS (2007) BS EN 15251 Indoor environmental input parameters for design and assessment of energy performance of buildings addressing indoor air quality, thermal environment, lighting and acoustics. London: British Standards Institute.} indoor air quality'
    # elif s_PAM=='CIBSE_thermal_comfort':
    #     s_PAMpreStr='CIBSE (2018)\\footnote{CIBSE (2018) Environmental design, CIBSE Guide A. Suffolk: CIBSE Publications.} thermal comfort'        

    s=r'''Analysis parameters
\begin{addmargin}[0.5cm]{0cm}
Request time: '''+s_date+' @ '+s_time+''' \\\\
Estate: '''+s_estate+''' \\\\
Estate type: '''+s_estateType+''' \\\\
Model: '''+s_building+''' \\\\
Assessment: '''+s_asmtName+''' \\\\
\\end{addmargin}
'''
    f_preamble=open('tmp/preamble.txt','w')
    f_preamble.write(s)
    f_preamble.close()

    # Check assessment script exists.
    s_asmtName=s_estateType.replace(' ','_')
    s_asmtScript='../../scripts/assessments/'+s_asmtName
    if not isfile(s_asmtScript):
        jobError(s_jobID,'resilience assessment script "'+s_asmtScript+'" not found',12,b_debug,f_log,s_shareDir)
    if b_debug: f_log.write('Resilience assessment name: '+s_asmtName+'\nResilience assessment script: '+s_asmtScript+'\n')

    # Assemble argument list, noting dummy cases.
    b_dummy=False
    s_tmpres='simulation_results'
    s_tmppdf='outputs/feedback.pdf'
    ls_args=['-d','tmp','-f',s_tmpres,'-r',s_tmppdf,'-P','tmp/preamble.txt',s_cfg]+['X' if a is None else a for a in ts_criteria]

    # Set handler so that the PAM will be killed if the job is killed.
    libc = ctypes.CDLL("libc.so.6")
    def set_pdeathsig(sig = signal.SIGKILL):
        def callable():
            return libc.prctl(1, sig)
        return callable

    if b_debug: 
        f_log.write('calling resilience assessment with command: '+' '.join([s_asmtScript]+ls_args)+'\n')

    # Send running signal.
    i_prgv=2
    con.send(i_prgv)

    # Run assessment.
    proc=Popen([s_asmtScript]+ls_args,stdout=PIPE,stderr=PIPE,preexec_fn=set_pdeathsig(signal.SIGKILL))

    # Read file tmp/progress.txt every second to keep track of progress.
    # Progress = ...
    # 1: job started
    # 2: starting RA
    # 3: RA checkpoint 1
    # 4: RA checkpoint 2
    # 5: RA checkpoint 3
    # 6: RA checkpoint 4
    # 7: RA checkpoint 5
    # 8: RA generating reports
    # 9: uploading results
    # 0: job complete
    s_prg='tmp/progress.txt'
    i_prgp=i_prgv
    while proc.poll()==None:
        sleep(1)
        if isfile(s_prg):
            f_prg=open(s_prg,'r')
            i_prgv=int(f_prg.readline().strip())
            f_prg.close()
        if i_prgv>i_prgp:
            con.send(i_prgv)
            i_prgp=i_prgv

    # Final progress value.
    if isfile(s_prg):
        f_prg=open(s_prg,'r')
        i_prgv=int(f_prg.readline().strip())
        f_prg.close()
    if i_prgv>i_prgp:
        con.send(i_prgv)

    t_tmp=(proc.stdout.read(),proc.stderr.read())

    if b_debug:
        f_log.write('\nPerformance assessment finished, output follows:\n'+t_tmp[0].decode()+'\n')
    if proc.returncode!=0:
        jobError(s_jobID,'Performance assessment failed.\n\nstderr:\n'+t_tmp[1].decode()+'\n\nstdout:\n'+t_tmp[0].decode()+'\n\n',proc.returncode,b_debug,f_log,s_shareDir)

    # Get performance flag.
    if not b_dummy:
        proc=Popen(['awk','-f','../../scripts/common/get_performanceFlag.awk','tmp/pflag.txt'],stdout=PIPE)
        t_tmp=proc.communicate()
        s_pFlag=t_tmp[0].decode().strip()
        if s_pFlag=='0':
            i_pFlag=0
        elif s_pFlag=='1':
            i_pFlag=1
        else:
            jobError(s_jobID,'Unrecognised compliance flag "'+s_pFlag+'"\n',18,b_debug,f_log,s_shareDir)

    # Upload job results.
    # Send uploading signal.
    i_prgv=9
    con.send(i_prgv)

    # If not a dummy RA, and the result is a fail, create tarball of simulation results and model (because you need the model to view results).
    if not b_dummy and i_pFlag==1:
        ls_simRes=glob('simulation_results.*')
        try:
            run(['tar','-czf','res.tar.gz','model']+ls_simRes,check=True)
        except:
            jobError(s_jobID,'Could not create simulation results tarball\n',18,b_debug,f_log,s_shareDir)
        else:
            run(['mv','-t','outputs','res.tar.gz'])
            run(['rm']+ls_simRes)

    if b_debug: f_log.write('Copying outputs to shared folder ...\n')
    s_DBjobDir=s_shareDir+'/Results/'+s_jobID
    try:
        rmtree(s_DBjobDir)
    except OSError:
        pass
    makedirs(s_DBjobDir)
    ls_outputs=glob('outputs/*')
    for s_output in ls_outputs:
        if b_debug: f_log.write('Copying '+basename(s_output)+' ...\n')
        if isfile(s_output):
            copyfile(s_output,s_DBjobDir+'/'+basename(s_output))
        elif isdir(s_output):            
            copytree(s_output,s_DBjobDir+'/'+basename(s_output))
        else:            
            jobError(s_jobID,'Could not copy file "'+s_output+'"\n',18,b_debug,f_log,s_shareDir)

    if b_debug: f_log.write('Done.\n')

    curDateTime=datetime.now()
    s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
    if b_debug: f_log.write('\n*** JOB FINISHED @ '+s_dateTime+' ***\n')
    if b_debug: f_log.close()

    # Upload log file to outputs folder if present.
    if b_debug:
        copyfile(s_jobID+'.log',s_DBjobDir+'/log.txt')

    # Send exit signal then performance flag.
    con.send(0)
    if b_dummy:
        # In dummy cases, just send a "compliant" signal.
        con.send(0)
    else:
        con.send(i_pFlag)

    # If job has got to this point, it was (hopefully) successful, so remove local job directory.
#    chdir('..')
#    rmtree(s_jobDir)

### END FUNCTION


### FUNCTION: jobError
# Writes an error file for a simulation job and exits with a fail code.
# If debugging, closes the log file. 
# Adds a datetime stamp to all messages.
# Writes error to json and pdf as well (currently not active).

def jobError(s_jobID,s_message,i_errorCode,b_debug,f_log,s_shareDir):
    curDateTime=datetime.now()
    s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
    f=open(s_jobID+'.err','w')
    f.write('Error @ '+s_dateTime+'\n\n')
    f.write(s_message)
    f.close()
    if b_debug: f_log.write('Error @ '+s_dateTime+'\n')

    # Error reports are no longer provided in the front end interface.
    # This functionality is commented for the time being.

# # Write error message into json and pdf.
#     f_json=open('outputs/data.json','w')
#     f_json.write('{"error": {\n'
#                  '  "datetime": "'+s_dateTime+'",\n'
#                  '  "code": "'+str(i_errorCode)+'",\n'
#                  '  "message": "'+s_message.replace('"','')+'"\n'
#                  '}}\n')
#     f_json.close()
#     s_pdf='outputs/report.tex'
#     f_pdf=open(s_pdf,'w')
#     f_pdf.write('\\nonstopmode\n\documentclass{report}\n\\begin{document}\n'+
#                 'The job did not successfully complete.\n'+
#                 'An error occured at '+s_dateTime+'.\n'+
#                 'Error message was:\n\n'+
#                 '\\begin{verbatim}\n'+
#                 s_message+'\n'+
#                 '\end{verbatim}\n\n'+
#                 '\end{document}')
#     f_pdf.close()
# #    run(['sed','-e',r's/\_/\\\_/g','-i',s_pdf])
#     f_pdfLog=open('pdflatex.out','w')
#     run(['pdflatex','-output-directory=outputs',s_pdf],stdout=f_pdfLog)
#     run(['pdflatex','-output-directory=outputs',s_pdf],stdout=f_pdfLog)
#     f_pdfLog.close()

#     # Copy results to shared folder.
#     if b_debug: f_log.write('Copying outputs to shared folder ...\n')
#     s_DBjobDir=s_shareDir+'/Results/'+s_jobID
#     try:
#         rmtree(s_DBjobDir)
#     except OSError:
#         pass
#     makedirs(s_DBjobDir)
#     copyfile('outputs/data.json',s_DBjobDir+'/data.json')
#     copyfile('outputs/report.pdf',s_DBjobDir+'/report.pdf')
#     if b_debug: f_log.write('Done.\n')    

    if b_debug: f_log.close()
    sys.exit(i_errorCode)

### END FUNCTION


### FUNCTION: sleepTilNext
# Checks the time elapsed since startTime (obtained from time() built-in),
# compares it with r_interval, and sleeps for any remaining time.
def sleepTilNext(start_time,r_interval,b_debug):
    end_time=time()
    time_taken=end_time-start_time
    if b_debug: print("Marathon: dispatch took "+'{:.2f}'.format(time_taken)+" seconds")
    if time_taken<r_interval:
        if b_debug: print('Marathon: sleeping for '+'{:.2f}'.format(r_interval-time_taken)+' seconds')
        sleep(r_interval-time_taken)
    else:
        if b_debug: print("Marathon: I'm late! I'm late!")

### END FUNCTION


### FUNCTION: getJobDir
# Takes the jobID and generates a job directory name from it.
# Creates a relative path from the location of this script,
# i.e. assumes that "../jobs" exists from the location of this script.
def getJobDir(s_jobID):
    s_jobDir=dirname(realpath(__file__))+'/../jobs/job_'+s_jobID
    return s_jobDir

### END FUNCTION


### FUNCTION: printError
# Prints a timestamped error message to the error log, and to the terminal if in debug mode.
def printError(s_msg,s_errlog,b_debug):    
    curDateTime=datetime.now()
    s_dateTime=curDateTime.strftime('%a %d %b %X %Y')
    f_errlog=open(s_errlog,'a')
    f_errlog.write(s_dateTime+': '+s_msg+'\n')
    f_errlog.close()
    if b_debug: print('Marathon error @ '+s_dateTime+': '+s_msg)

### END FUNCTION



        


def main():

    setproctitle('marathon')

    # Set defaults.
    r_interval=15
    b_debug=False
    i_failLimit=10

    # Parse command line.
    i_argCount=0
    for arg in sys.argv[1:]:
        if arg[0]=='-':
            # This is an option.
            if arg=='-h' or arg=='--help':
                print('''
main.py
This is the back end simulation service for the Marathon service. Once
invoked, this program will run in an infinite loop until a fatal error
occurs or the process is terminated. Simulation jobs, requested by the
Marathon front end, will be spawned as seperate processes in parallel.
The process of checking jobs is termed a dispatch, and happens at 
intervals determined by a command line argument. Communication between 
the front and back ends is accomplished by an SQL database and a shared 
directory tree, see documentation for details.

Usage:
./main.py -h
./main.py [-d] path-to-shared-folder [dispatch-interval]

Command line options:
-h, --help  - displays help text
-d, --debug - service prints debug information to standard out,
              and jobs print debug information to "[jobID].log"
              in the job folder (../jobs/job_[jobID]).

Command line arguments:
1: path to shared folder
2: [optional] dispatch interval in seconds (default 15)''')
                sys.exit(0)
            elif arg=='-d' or arg=='--debug':
                b_debug=True
            else:
                print('Marathon error: unknown command line option "'+arg+'"',file=sys.stderr)
                sys.exit(1)
        else:
            # This is an argument.
            i_argCount=i_argCount+1
            if i_argCount==1:
                s_shareDir=arg
                if s_shareDir[-1]=='/': s_shareDir=s_shareDir[:-1]
            elif i_argCount==2:
                try:
                    r_interval=float(arg)
                except ValueError:
                    print('Marathon error: interval argument is not a number',file=sys.stderr)
                    sys.exit(1)
    if i_argCount<1 or i_argCount>2:
        print('Marathon error: script accepts 1 or 2 argument(s)',file=sys.stderr)
        sys.exit(1)

    # Main program.

    curDateTime=datetime.now()
    s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
    if b_debug: print('Marathon: SERVICE START @ '+s_dateTime)

    # Create dictionaries to hold all running processes and pipe connections.
    # They can be retrieved by job ID (string).
    dict_proc=dict()
    dict_pipe=dict()

    ### FUNCTION: killItWithFire
    # Kills a job with extreme prejudice. Sends a SIGKILL and erases the job directory.
    # This can be used if a job starts to look fishy.
    # Assumes that the job exists and is alive.
    def killItWithFire(s_jobID):
        proc=dict_proc[s_jobID]
        kill(proc.pid,signal.SIGKILL)
        rmtree(getJobDir(s_jobID))
        con,sender=dict_pipe[s_jobID]
        con.close()
        sender.close()
        del dict_proc[s_jobID]
        del dict_pipe[s_jobID]

    # Dispatch in infinite loop.
    while True:
        curDateTime=datetime.now()
        s_dateTime=curDateTime.strftime('%a %b %d %X %Y')
        if b_debug: print('Marathon: --------------------\nMarathon: starting dispatch @ '+s_dateTime)
        # Get current time, to time how long dispatch takes.
        start_time=time()

        # Get SQL database IP from file.
        f_SQL=open('.SQL.txt','r')
        s_SQLIP=f_SQL.readline().strip()
        s_SQLuser=f_SQL.readline().strip()
        s_SQLpwd=f_SQL.readline().strip()
        s_SQLdbs=f_SQL.readline().strip()
        s_errlog=f_SQL.readline().strip()
        f_SQL.close()
        if b_debug: print('Marathon: connecting to SQL database at IP '+s_SQLIP)

        # Connect to SQL database.
        try:
            cnx=connector.connect(user=s_SQLuser,
                password=s_SQLpwd,
                host=s_SQLIP,
                database=s_SQLdbs,
                connection_timeout=r_interval)
        except:
            printError('failed to connect to SQL database, skipping dispatch',s_errlog,b_debug)
            sleepTilNext(start_time,r_interval,b_debug)
            continue
        cursor=cnx.cursor(buffered=True)

        ### FUNCTION: sql_update
        # Updates the sql table with a new "result" value.
        def sql_update(i_update,i_jobID):
            try:
                cursor.execute("UPDATE results SET result = {:d} WHERE id = {:d}".format(i_update,i_jobID))
                cnx.commit()
            except:
                printError('failed to update SQL database',s_errlog,b_debug)
            else:
                if b_debug: print('Marathon: successfully updated the SQL database')

        # Retrieve job list from SQL database.
        try:
            cursor.execute("SELECT id,model,result,preset,name FROM results")
            query=cursor.fetchall()
        except:
            printError('failed to query SQL database, skipping dispatch',s_errlog,b_debug)
            sleepTilNext(start_time,r_interval,b_debug)
            continue
        else:
            if b_debug: print('Marathon: successfully queried the SQL database')

        # Check for required actions on jobs
        for (i_jobID,i_model,i_progress,i_preset,s_asmtName) in query:

            # Retrieve model details.
            try:
                cursor.execute("SELECT tarball,name,estate,md5 FROM models WHERE id = "+str(i_model))
                model_query=cursor.fetchall()
            except:
                i_update=9
                printError('failed to retrieve model details for job ID {:d}'.format(i_model),s_errlog,b_debug)
                sql_update(i_update,i_jobID)
                continue
            else:
                (s_tarball,s_building,i_estate,s_MD5)=model_query[0]

            # Retrieve estate name and type.
            try:
                cursor.execute("SELECT estates.name,estate_types.type FROM estates INNER JOIN estate_types ON estates.type=estate_types.id WHERE estates.id = "+str(i_estate))
                model_query=cursor.fetchall()
            except:
                i_update=9
                printError('failed to retrieve name and/or type of estate ID {:d}'.format(i_estate),s_errlog,b_debug)
                sql_update(i_update,i_jobID)
                continue
            else:
                (s_estate,s_estateType)=model_query[0]

            # Retrieve criteria.
            try:
                cursor.execute("SELECT is_custom FROM presets WHERE id = "+str(i_preset))
                model_query=cursor.fetchall()
            except:
                i_update=9
                printError('failed to retrieve custom flag of preset id {:d}'.format(i_preset),s_errlog,b_debug)
                sql_update(i_update,i_jobID)
                continue
            else:
                (i_isCustom)=model_query[0]

            if (i_isCustom==1):
                s_asmtName=s_asmtName.capitalize()+' (custom)'
                try:
                    cursor.execute('''SELECT 
in01,in02,in03,in04,in05,in06,in07,in08,in09,in10,
in11,in12,in13,in14,in15,in16,in17,in18,in19,in20,
in21,in22,in23,in24,in25,in26,in27,in28,in29,in30
FROM model_inputs WHERE result = '''+str(i_jobID))
                    model_query=cursor.fetchall()
                except:
                    i_update=9
                    printError('failed to retrieve criteria of custom assessment for job id {:d}'.format(i_jobID),s_errlog,b_debug)
                    sql_update(i_update,i_jobID)
                    continue
                else:
                    ts_criteria=model_query[0]
            else:
                s_asmtName=s_asmtName.capitalize()
                try:
                    cursor.execute('''SELECT 
in01,in02,in03,in04,in05,in06,in07,in08,in09,in10,
in11,in12,in13,in14,in15,in16,in17,in18,in19,in20,
in21,in22,in23,in24,in25,in26,in27,in28,in29,in30
FROM presets WHERE id = '''+str(i_preset))
                    model_query=cursor.fetchall()
                except:
                    i_update=9
                    printError('failed to retrieve criteria of preset {:d} for job id {:d}'.format(i_preset,i_jobID),s_errlog,b_debug)
                    sql_update(i_update,i_jobID)
                    continue
                else:
                    ts_criteria=model_query[0]


            # Check stage of this job.
            s_jobID=str(i_jobID)
            i_update=-1

            # i_update values:
            # None: pending (not submitted yet)
            # 0: run requested
            # 1: running
            # 11 - 19: running with progress indicator
            # 2: suspended
            # 3: complete
            # 4: abandoned
            # 5: -
            # 6: -
            # 7: cancel requested
            # 8: cancelled
            # 9: job error

            if i_progress==None:
                if b_debug:
                    print('Marathon: *** pending job ***')
                    print('Marathon:   jobID - '+s_jobID)
                    print('Marathon:   building - '+s_building)
                    print('Marathon:   estate type - '+s_estateType)
                    print('Marathon:   resilience assessment - '+s_asmtName)

            elif i_progress==0:
                # Start a job - python multiprocessing.
                # Check that a job with this ID doesn't already exist.
                if s_jobID in dict_proc:
                    if b_debug: print('Marathon: job with ID '+s_jobID+' already exists')
                    i_update=1
                    sql_update(i_update,i_jobID)
                    continue

                if b_debug:
                    print('Marathon: *** starting new job ***')
                    print('Marathon:   jobID - '+s_jobID)
                    print('Marathon:   building - '+s_building)
                    print('Marathon:   estate type - '+s_estateType)
                    print('Marathon:   resilience assessment - '+s_asmtName)

                # Open a unidirectional pipe (slave->master) so the process can communicate its status.
                con,sender=Pipe(False)

                # Debug - run fake job
                # proc=Process(target=runFakeJob,name='jobID_'+s_jobID,args=(s_jobID,))
                proc=Process(target=runJob,name='jobID_'+s_jobID,args=(s_jobID,s_tarball,s_MD5,s_building,s_estate,s_estateType,s_asmtName,ts_criteria,b_debug,sender,s_shareDir))
                proc.start()

                # Put the process and pipe connections into a dictionary for later retrieval.
                dict_proc[s_jobID]=proc
                dict_pipe[s_jobID]=(con,sender)
                i_update=1

            elif i_progress==1 or (i_progress>10 and i_progress<20):

                # Check status of currently running job - python multiprocessing.

                if b_debug:
                    print('Marathon: ### checking status of job ###')
                    print('Marathon:   jobID - '+s_jobID)
                    print('Marathon:   building - '+s_building)
                    print('Marathon:   estate type - '+s_estateType)
                    print('Marathon:   resilience assessment - '+s_asmtName)
                # Retrieve job and connection objects from dictionaries.
                if not s_jobID in dict_proc or not s_jobID in dict_pipe:
                    # Job says it is running, but it not registered.
                    # This probably means the service crashed and has been restarted.
                    # Restart the job ... unless there is a kill file in the job directory.
                    if b_debug: print('Marathon:   jobID not registered')

                    if isfile(getJobDir(s_jobID)+'/kill.it'):
                        if b_debug: print('Marathon: !!! kill file detected !!!')
                        i_update=8
                        sql_update(i_update,i_jobID)
                        continue                        

                    if b_debug: print('Marathon: *** restarting job ***')

                    if s_jobID in dict_proc: del dict_proc[s_jobID]
                    if s_jobID in dict_pipe: del dict_pipe[s_jobID]
                    con,sender=Pipe(False)

                    # Debug - run fake job
                    # proc=Process(target=runFakeJob,name='jobID_'+s_jobID,args=(s_jobID,))
                    proc=Process(target=runJob,name='jobID_'+s_jobID,args=(s_jobID,s_tarball,s_MD5,s_building,s_estate,s_estateType,s_asmtName,ts_criteria,b_debug,sender,s_shareDir))
                    proc.start()

                    # Put the process and pipe connections into a dictionary for later retrieval.
                    dict_proc[s_jobID]=proc
                    dict_pipe[s_jobID]=(con,sender)                    
                    continue

                # Check for an admin kill command (a file called "kill.it" in the job directory).
                if isfile(getJobDir(s_jobID)+'/kill.it'):
                    if b_debug: print('Marathon: !!! kill file detected !!!')
                    killItWithFire(s_jobID)
                    i_update=8
                    sql_update(i_update,i_jobID)
                    continue

                proc=dict_proc[s_jobID]
                con,sender=dict_pipe[s_jobID]
                if proc.is_alive():
                    # Job is still alive, check its status.
                    i_tmp=-1
                    b_done=False
                    if b_debug: print('Marathon:   job is alive')
                    while con.poll():
                        i_tmp=con.recv()
                        if not type(i_tmp)==int:
                            # Unexpected signal type.
                            i_tmp=None
                            break
                        if b_debug: print('Marathon:   job gave signal "'+str(i_tmp)+'"')
                        if i_tmp==0:
                            b_done=True
                    if b_done:                        
                        # Exit signal recieved but job is still running.
                        # Wait half a second then check again.
                        sleep(0.5)
                        if proc.is_alive():
                            # This shouldn't really be possible, so something odd is going on.
                            # Kill the job just to be safe.
                            # TODO - maybe check outputs?
                            killItWithFire(s_jobID)
                            printError('job ID {:d} continued to run after exit signal; killed'.format(i_model),s_errlog,b_debug)
                            i_update=9
                        elif proc.exitcode==0:
                            if i_tmp==0:
                                # Check if the performance flag is still in the pipe.
                                if con.poll():
                                    i_tmp=con.recv()
                                else:
                                    # This shouldn't be possible.
                                    printError('job ID {:d} didn\'t give performance flag'.format(i_model),s_errlog,b_debug)
                                    i_update=9
                            if i_tmp==0: 
                                i_update=3 # pass
                            elif i_tmp==1: 
                                i_update=2 # fail
                            else:
                                # Unexpected performance flag.
                                # Again, this shouldn't really be possible.
                                printError('job ID {:d} gave unrecognised performance flag'.format(i_model),s_errlog,b_debug)
                                i_update=9
                        else:
                            i_update=9
                        # Close pipe and remove dictionary entries.
                        sender.close()
                        con.close()
                        del dict_proc[s_jobID]
                        del dict_pipe[s_jobID]
                    elif i_tmp>0 and i_tmp<10:
                        # Job has updated
                        i_update=10+i_tmp
                    elif i_tmp==-1:
                        # No update from job
                        i_update=0
                    else:
                        # Unexpected signal from job - kill it with fire!
                        killItWithFire(s_jobID)
                        printError('job ID {:d} gave unexpected signal; killed'.format(i_model),s_errlog,b_debug)
                        i_update=9
                else:
                    # Job is dead, check exit code and make sure it gave the expected exit signal.
                    sender.close()
                    i_tmp=-1
                    b_done=False
                    if b_debug: print('Marathon:   job is dead')
                    while con.poll():
                        try: 
                            i_tmp_prev=i_tmp
                            i_tmp=con.recv()
                        except EOFError:
                            # Trap this error to avoid crashing the service.
                            i_tmp=i_tmp_prev
                            break
                        if b_debug: print('Marathon:   job gave signal "'+str(i_tmp)+'"')
                        if i_tmp==0:
                            b_done=True
                    con.close()
                    if b_done and proc.exitcode==0:                        
                        if i_tmp==0: 
                            i_update=3
                        elif i_tmp==1: 
                            i_update=2
                        else:
                            # Unexpected performance flag.
                            # This shouldn't really be possible.
                            printError('job ID {:d} gave unrecognised performance flag'.format(i_model),s_errlog,b_debug)
                            i_update=9
                    elif proc.exitcode!=0:
                        printError('job ID {:d} failed'.format(i_model),s_errlog,b_debug)
                        i_update=9
                    else:
                        printError('job ID {:d} didn\'t give exit signal'.format(i_model),s_errlog,b_debug)
                        i_update=9
                    # Remove dictionary entries.
                    del dict_proc[s_jobID]
                    del dict_pipe[s_jobID]

                if i_update==2 or i_update==3 or i_update==4:
                    if b_debug: print('Marathon: *** job complete ***')

                elif i_update==1:
                    if b_debug: print('Marathon: *** job requested ***')

                elif i_update>10 and i_update<20:
                    if b_debug: print('Marathon: *** job still running ***')

                elif i_update==9:
                    if b_debug: print('Marathon: !!! job failed !!!')

            elif i_progress==7:
                # Cancel a job.
                if b_debug:
                    print('Marathon: ### cancelling job ###')
                    print('Marathon:   jobID - '+s_jobID)
                    print('Marathon:   building - '+s_building)
                    print('Marathon:   estate type - '+s_estateType)
                    print('Marathon:   resilience assessment - '+s_asmtName)
                # Retrieve job and connection objects from dictionaries.
                if not s_jobID in dict_proc or not s_jobID in dict_pipe:
                    if b_debug: print('Marathon:   jobID not registered')
                    if b_debug: print('Marathon: *** non-existent job flagged as cancelled ***')
                    i_update=8
                    sql_update(i_update,i_jobID)
                    continue
                proc=dict_proc[s_jobID]
                con,sender=dict_pipe[s_jobID]
                if proc.is_alive():
                    # Job is still alive, terminate it.
                    if b_debug: print('Marathon:   job is alive')
                    proc.terminate()
                    slept=0
                    b_zombie=False
                    while proc.is_alive():
                        sleep(0.1)
                        slept+=1
                        if slept>50:
                            printError('process Marathon'+s_jobID+' left zombified',s_errlog,b_debug)
                            b_zombie=True
                            break
                    if not b_zombie: proc.join()
                    sender.close()
                    con.close()
                    del dict_proc[s_jobID]
                    del dict_pipe[s_jobID]
                    i_update=8
                    if b_debug: print('Marathon: *** job cancelled ***')
                else:
                    # Job is dead, check exit code and make sure it gave the expected exit signal.
                    sender.close()
                    i_tmp=0
                    b_done=False
                    if b_debug: print('Marathon:   job is dead')
                    while con.poll():
                        try: 
                            i_tmp_prev=i_tmp
                            i_tmp=con.recv()
                        except EOFError:
                            # Trap this error to avoid crashing the service.
                            i_tmp=i_tmp_prev
                            break
                        if b_debug: print('Marathon:   job gave signal "'+str(i_tmp)+'"')
                        if i_tmp==4:
                            b_done=True
                    con.close()
                    if b_done and proc.exitcode==0:                     
                        if i_tmp==0: 
                            i_update=3
                        elif i_tmp==1: 
                            i_update=2
                        else:
                            # Unexpected performance flag.
                            # This shouldn't really be possible.
                            if b_debug: print('Marathon: !!! job gave unrecognised performance flag !!!')
                            i_update=9
                    elif proc.exitcode!=0:
                        printError('job ID {:d} failed'.format(i_model),s_errlog,b_debug)
                        i_update=9
                    else:
                        if b_debug: print('Marathon: !!! job didn\'t give exit signal !!!')
                        i_update=9
                    # Remove dictionary entries.
                    del dict_proc[s_jobID]
                    del dict_pipe[s_jobID]

                    if i_update==2 or i_update==3 or i_update==4:
                        if b_debug: print('Marathon: *** job complete ***')

                    elif i_update==9:
                        printError('job ID {:d} failed'.format(i_model),s_errlog,b_debug)
            
            # Update sql database with new job status.
            if i_update>0:
                sql_update(i_update,i_jobID)

        cnx.close()

        # Check that dispatch has not been running for longer than the interval.
        sleepTilNext(start_time,r_interval,b_debug)

if __name__=='__main__': main()
