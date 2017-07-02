###############################################################################
#
# f06 summary extraction script
#
# created by Jens M Hebisch
#
# Version 0.3
# V0.2 Output Eigenvalues and Cycles
# V0.3 Output simple difference instead of percentage difference
# also, because SPC + OLOAD = 0 signs in the percentage difference formula are
# switched. % Diff Forumla is still available and can be uncommented if 
# required.
#
# This script is intended to extract useful information from f06 files.
# The script has two modes:
# Mode 1: provide a f06 file to operate on as in:
# perl f06_validation_extraction.pl Analysis.f06
# This will extract the information from the f06 file provided. Multiple files
# can be provided. Files or inputs that do not end in f06 will be discarded.
#
# Mode 2: provide the parameter find as in:
# perl f06_summary_extraction.pl find
# This will extract data from all f06 files in this and all sub directories
# (only one one level deep)
#
# output will be presented in files using the name of the f06 file with the
# extension f06log. Files will be output in the folder from which the script
# is run. Existing f06log files will be overwritten without without warning.
# Output is tab separated to allow easy pasting into spreadsheets or tables
#
# This script has been tested against the f06 files provided with PYNASTRAN
#
###############################################################################
use warnings;
use strict;
use Cwd;

my @files;
my $outputDir = cwd();

sub getF06Files {
	#input: path (to concatenate with file name, not used to change directory)
	#output: array with f06 files
	my $path = $_[0];
	my @tempFiles = <*.f06>;
	my @f06files;
	foreach my $file (@tempFiles){
		push(@f06files,$path."/".$file);
	}
	return @f06files;
}

#explanations to warning codes can be added here
my %knownWarnings = (
	324 => "Blank lines in input files.",
	4124 => "The SPCADD or MPCADD union consists of a single set.",
	4698 => "High factor diagonal ratio or negative terms in factor diagonal.",
);
my %knownFatals = (
	9050 => "Insufficient Constraints.",
	3019 => "Maximum line count exceeded in subroutine pager.",
);


#get f06 files from input
if(not @ARGV){
	print "No input was provided. Program will now terminate.\n";
	exit;
}
elsif($ARGV[0] eq "find"){
	#look for files in directories
	#push including path so they can be opened form a different directory
	#current directory
	push(@files,getF06Files("."));
	#sub directory
	opendir(my $dh, $outputDir);
	my @dirs = grep {-d "$outputDir/$_" && ! /^\.{1,2}$/} readdir($dh);
	foreach my $path (@dirs){
		chdir($path);
		push(@files,getF06Files("./".$path));
		chdir("..");
	}
}
else{
	foreach my $file (@ARGV){
		if($file =~ m/\.f06$/){
			push(@files, $file);
		}
	}
}
chdir($outputDir);

#process f06 files
foreach my $file (@files){
	print "Processing\t".$file."\n";
	open(IPT, "<", $file) or die "could not open $file.\n";
	my @fileNameParts = split("/",$file);
	open(OPT, ">", $fileNameParts[-1]."log") or die "could not create $fileNameParts[-1]"."log.\n";
	my $starCounter = 0;
	my $lineCounter = 0;
	my $mSumSwitch = 0;
	my $GPSSwitch = 0;
	my $failedElmSwitch = 0;
	my $OLOADSwitch = 0;
	my $SPCFSwitch = 0;
	my $epsilonSwitch = 0;
	my $maxDisplSwitch = 0;
	my $EigenVSwitch = 0;
	my $massSwitch = 0;
	my $nastranType = "not set";
	my $nastranVersion = "not set";
	my $computerSystem = "not set";
	my $computerModel = "not set";
	my $operatingSystem = "not set";
	my $type = 0;
	my $eoj = 0;
	my %fatals;
	my %warnings;
	my @modelSummary;
	my %GPS;
	my $mfd;
	my $mass;
	my @failedElements;
	my $subcase;
	my %OLOAD;
	my %SPCF;
	my @epsilon;
	my @maxDispl;
	my @eigenV;
	while(<IPT>){
		#computer information
		#set up for NX NASTRAN and MSC.Nastran
		#other nastran types may format this section differently
		if(m/(\* ){19}/){
			$starCounter++;
		}
		#End of job
		elsif(m/\* \* \* END OF JOB \* \* \*/){
			$eoj = 1;
		}
		#Matrix to Factor Diagonal Ratio
		elsif(m/YIELDS A MAXIMUM MATRIX-TO-FACTOR-DIAGONAL RATIO OF\s+(\S+)/){
			$mfd = $1;
		}
		#Switches
		elsif(m/^1/){
			$GPSSwitch = 0;
			$mSumSwitch = 0;
			$failedElmSwitch = 0;
			$OLOADSwitch = 0;
			$SPCFSwitch = 0;
			$epsilonSwitch = 0;
			$maxDisplSwitch = 0;
			$EigenVSwitch = 0;
		}
		
		elsif(m/^ \*\*\* USER INFORMATION MESSAGE (\d+)/){
			$mSumSwitch = 0;
		}
		elsif(m/ \*\*\* SYSTEM INFORMATION MESSAGE (\d+)/){
			$GPSSwitch = 0;
		}
		elsif($starCounter == 2){
			if($lineCounter == 4){
				if(m/\* \*\s+(.*?)\s+\* \*/){
					$nastranType = $1;
				}
				if($nastranType eq "N X   N a s t r a n"){
					$type = 2;
				}
				elsif($nastranType eq "M S C . N a s t r a n" or $nastranType eq "M S C   N a s t r a n"){
					$type = 1;
				}
			}
			elsif(m/Version (\S+)/ and $type == 1){
				$nastranVersion = $1;
			}
			elsif($lineCounter == 6 and $type == 2){
				if(m/\* \*\s*(.*?)\s*\* \*/){
					$nastranVersion = $1;
				}
			}
			elsif($lineCounter == 14 and $type == 1){
				if(m/\* \*\s*(.*?)\s*\* \*/){
					$computerSystem = $1;
				}
			}
			elsif($lineCounter == 13 and $type == 2){
				if(m/\* \*\s*(.*?)\s*\* \*/){
					$computerSystem = $1;
				}
			}
			elsif(m/MODEL\s*(.*?)\s*\* \*/ and $type == 1){
				$computerModel = $1;
			}
			elsif($lineCounter == 11 and $type == 2){
				if(m/\* \*\s*(.*?)\s*\* \*/){
					$computerModel = $1;
				}
			}
			elsif($lineCounter == 16 and $type == 1){
				if(m/\* \*\s*(.*?)\s*\* \*/){
					$operatingSystem = $1;
				}
			}
			elsif($lineCounter == 15 and $type == 2){
				if(m/\* \*\s*(.*?)\s*\* \*/){
					$operatingSystem = $1;
				}
			}
			$lineCounter++;
		}
		#FATAL
		elsif(m/USER FATAL MESSAGE\s+(\d+)/){
			$fatals{$1} = 1;
		}
		#WARNING
		elsif(m/USER WARNING MESSAGE\s+(\d+)/){
			$warnings{$1} = 1;
		}
		#Model Summary
		elsif(m/M O D E L   S U M M A R Y/){
			$mSumSwitch = 1;
		}
		elsif($mSumSwitch){
			if(m/\s+(\S+.*?)\s+(\d+)/){
				push(@modelSummary, $1."\t".$2);
			}
		}
		#Grid Point Singularity Table
		elsif(m/G R I D   P O I N T   S I N G U L A R I T Y   T A B L E/){
			$GPSSwitch = 1;
		}
		elsif($GPSSwitch){
			if(m/^\s+(\d+)\s+G\s+(\d)/){
				if($GPS{$1}){
					$GPS{$1}[$2-1] = "X";
				}
				else{
					$GPS{$1} = [" "," "," "," "," "," "];
					$GPS{$1}[$2-1] = "X";
				}
			}
		}
		#Mass
		elsif(m/\s+MASS AXIS SYSTEM \(S\)\s+MASS\s+X-C\.G\.\s+Y-C\.G\.\s+Z-C\.G\./){
			$massSwitch = 1;
		}
		elsif($massSwitch){
			if(m/\s+X\s+(\S+)/){
				$mass = $1;
			}
			$massSwitch = 0;
		}
		#Failed Elements
		elsif(m/ ELEMENT TYPE\s+ID\s+SKEW ANGLE\s+MIN INT. ANGLE\s+MAX INT. ANGLE\s+WARPING FACTOR\s+TAPER RATIO/){
			$failedElmSwitch = 1;
		}
		elsif($failedElmSwitch){
			if(m/\s+(\S+)\s+(\d+)/){
				push(@failedElements,$1."\t".$2);
			}
		}
		#OLOAD RESULTANT
		elsif(m/OLOAD\s+RESULTANT/){
			$OLOADSwitch = 1;
		}
		elsif($OLOADSwitch){
			if(m/^0\s+(\d+)/){
				$subcase = $1;
			}
			elsif(m/\s+TOTALS\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/){
				$OLOAD{$subcase} = [$1,$2,$3,$4,$5,$6];
			}
		}
		#SPCFORCE RESULTANT
		elsif(m/SPCFORCE\s+RESULTANT/){
			$SPCFSwitch = 1;
		}
		elsif($SPCFSwitch){
			if(m/^0\s+(\d+)/){
				$subcase = $1;
			}
			elsif(m/\s+TOTALS\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/){
				$SPCF{$subcase} = [$1,$2,$3,$4,$5,$6];
			}
		}
		#Epsilon, External Load
		elsif(m/\s+LOAD SEQ. NO.\s+EPSILON\s+EXTERNAL WORK/){
			$epsilonSwitch = 1;
		}
		elsif($epsilonSwitch){
			if(m/^\s+(\d+)\s+(\S+)\s+(\S+)$/){
				push(@epsilon,$1."\t".$2."\t".$3."\t");
			}
		}
		#MAXIMUM  DISPLACEMENTS
		elsif(m/MAXIMUM  DISPLACEMENTS/){
			$maxDisplSwitch = 1;
		}
		elsif($maxDisplSwitch){
			if(m/0\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/){
				push(@maxDispl,$1."\t".$2."\t".$3."\t".$4."\t".$5."\t".$6."\t".$7);
			}
		}
		#Eigen Values
		elsif(m/R E A L   E I G E N V A L U E S/){
			$EigenVSwitch = 1;
		}
		elsif($EigenVSwitch){
			if(m/\s+(\d+)\s+\d+\s+(\S+)\s+\S+\s+(\S+)/){
				 push(@eigenV,$1."\t".$2."\t".$3);
			}
		}

	}
	#print data
	#computer information
	print OPT ("-"x80)."\n";
	print OPT "COMPUTER SYSTEM INFORMATION\n";
	print OPT "Nastran Version:\t$nastranType\n";
	print OPT "Release:\t$nastranVersion\n";
	print OPT "System:\t$computerSystem\n";
	print OPT "Model:\t$computerModel\n";
	print OPT "Operating System:\t$operatingSystem\n";
	print OPT ("-"x80)."\n";
	#End of Job
	if(not $eoj){
		print OPT "***WARNING*** No End of Job line found. Run may not have completed.\n";
		print OPT ("-"x80)."\n";
	}
	#Fatals
	if(%fatals){
		print OPT "***WARNING*** The Following FATAL codes were found:\n";
		foreach my $code (keys(%fatals)){
			print OPT $code;
			if($knownFatals{$code}){
				print OPT "\t$knownFatals{$code}";
			}
			print OPT "\n";
		}
	}
	else{
		print OPT "No Fatal Errors were found.\n";
	}
	print OPT ("-"x80)."\n";
	#Warnings
	if(%warnings){
		print OPT "The Following Warning codes were found:\n";
		foreach my $code (keys(%warnings)){
			print OPT $code;
			if($knownWarnings{$code}){
				print OPT "\t$knownWarnings{$code}";
			}
			print OPT "\n";
		}
	}
	else{
		print OPT "No Warnings were found.\n";
	}
	print OPT ("-"x80)."\n";
	#Model Summary
	if(@modelSummary){
		print OPT "MODEL SUMMARY\n";
		print OPT "Element Type\tCount\n";
		foreach my $line (@modelSummary){
			print OPT $line."\n";
		}
		print OPT ("-"x80)."\n";
	}
	#Failed Elements
	if(@failedElements){
		print OPT "ELEMENTS THAT FAILED NASTRAN CHECKS\n";
		my %failedElm;
		foreach my $line (@failedElements){
			unless($failedElm{$line}){
				print OPT $line."\n";
				$failedElm{$line} = 1;
			}
		}
		print OPT ("-"x80)."\n";
	}
	#Mass
	if($mass){
		print OPT "MODEL MASS (units depend on WTMASS and density assigned to the Material cards)\n";
		print OPT $mass."\n";
		print OPT ("-"x80)."\n";
	}
	#Grid Point Singularity Table
	if(%GPS){
		print OPT "GRID POINT SINGULARITY TABLE\n";
		print OPT "Element\\DOF\t1\t2\t3\t4\t5\t6\n";
		my @ids = sort({$a <=> $b} keys(%GPS));
		foreach my $id (@ids){
			print OPT $id;
			foreach my $dof (@{$GPS{$id}}){
				print OPT "\t".$dof;
			}
			print OPT "\n";
		}
		print OPT ("-"x80)."\n";
	}
	#Matrix to Factor Diagonal Ratio
	if($mfd){
		print OPT "MAXIMUM MATRIX-TO-FACTOR-DIAGONAL RATIO\n";
		print OPT $mfd."\n";
		print OPT ("-"x80)."\n";
	}
	#OLOAD and SPCForce balance
	if(%OLOAD and %SPCF){
		print OPT "OLOAD AND SPC FORCE BALANCE\n";
		print OPT "Label\tSubcase\tT1\tT2\tT3\tR1\tR2\tR3\n";
		my @subcases = sort({$a <=> $b} keys(%OLOAD));
		foreach my $subcase (@subcases){
			print OPT "OLOAD\t".$subcase;
			foreach my $value (@{$OLOAD{$subcase}}){
				print OPT "\t".$value;
			}
			print OPT "\n";
			print OPT "SPCFORCE\t".$subcase;
			foreach my $value (@{$SPCF{$subcase}}){
				print OPT "\t".$value;
			}
			print OPT "\n";
			print OPT "\DIFF\t".$subcase;
			for(my $n = 0; $n<6; $n++){
				if(abs($SPCF{$subcase}[$n]+$OLOAD{$subcase}[$n]) == 0){
					print OPT "\t0";
				}
				else{
					#OLOAD + SPCF should be = 0 therefore difference formula signs must be switched
					#percentage difference
					#print OPT "\t".(abs($SPCF{$subcase}[$n]+$OLOAD{$subcase}[$n])*200/abs($SPCF{$subcase}[$n]-$OLOAD{$subcase}[$n]))
					#simple difference
					print OPT "\t".($SPCF{$subcase}[$n]+$OLOAD{$subcase}[$n]);
				}
			}
			print OPT "\n";
		}
		print OPT ("-"x80)."\n";
	}
	#Epsilon and External Work
	if(@epsilon){
		print OPT "EPSILON AND EXTERNAL WORK\n";
		print OPT "Subcase\tEpsilon\tExternal Work\n";
		foreach my $line (@epsilon){
			print OPT $line."\n";
		}
		print OPT ("-"x80)."\n";
	}
	#Max Displacement
	if(@maxDispl){
		print OPT "MAXIMUM DISPLACEMENTS\n";
		print OPT "Subcase\tT1\tT2\tT3\tR1\tR2\tR3\n";
		foreach my $line (@maxDispl){
			print OPT $line."\n";
		}
		print OPT ("-"x80)."\n";
	}
	#Eigen Values
	if(@eigenV){
		print OPT "EIGENVLAUES\n";
		print OPT "Mode\tEigenvalue\tCycles\n";
		foreach my $line (@eigenV){
			print OPT $line."\n";
		}
		print OPT ("-"x80)."\n";
	}
	close(IPT);
	close(OPT);
}
