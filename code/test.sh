#!/bin/bash
#SBATCH --job-name=freesurfer_group
#SBATCH --output=logs/%x_%j.out 
#SBATCH --nodes=1
#SBATCH --cpus-per-task=40
#SBATCH --time=00:15:00
#SBATCH --array=0-9


## set the second environment variable to get the base directory
BASEDIR=${SLURM_SUBMIT_DIR}

export BIDS_DIR=${BASEDIR}/data/local/bids
export SING_CONTAINER=${BASEDIR}/containers/freesurfer-7.4.1.simg 
export LOGS_DIR=${BASEDIR}/logs
export ORIG_FS_LICENSE=${BASEDIR}/templates/.freesurfer.txt
export SUBJECTS_DIR=${BASEDIR}/data/local/freesurfer
export GCS_FILE_DIR=${BASEDIR}/templates/freesurfer_parcellate

# Assign subjects in batches of 10 (adjust the batch size if needed)
SUBJECTS_FILE=$BIDS_DIR/participants.tsv
SUBJECTS=$(tail -n +2 $SUBJECTS_FILE | cut -f1)

# Get the current subject batch based on SLURM_ARRAY_TASK_ID
BATCH_SIZE=10
START_INDEX=$((SLURM_ARRAY_TASK_ID * BATCH_SIZE))
END_INDEX=$((START_INDEX + BATCH_SIZE - 1))
SUBJECT_BATCH=$(echo $SUBJECTS | awk -v start=$START_INDEX -v end=$END_INDEX '{for(i=start; i<=end; i++) print $i}')



singularity exec \
    -B ${BASEDIR}/templates:/home/freesurfer --home /home/freesurfer \
    -B ${BIDS_DIR}:/bids \
    -B ${ORIG_FS_LICENSE}:/li \
    -B ${SUBJECTS_DIR}:/subjects_dir \
    -B ${GCS_FILE_DIR}:/gcs_files \
    --env SUBJECT_BATCH="$SUBJECT_BATCH" \
    ${SING_CONTAINER} /bin/bash << "EOF"


      export SUBJECTS_DIR=/subjects_dir

      # List all lh and rh GCS files in the directory
      LH_GCS_FILES=(/gcs_files/lh.*.gcs)
      RH_GCS_FILES=(/gcs_files/rh.*.gcs)

      # Loop over each subject
      for SUBJECT in $SUBJECT_BATCH; do
      
        SUBJECT_LONG_DIRS=$(find $SUBJECTS_DIR -maxdepth 1 -name "${SUBJECT}*" -type d)
        
        for SUBJECT_LONG_DIR in $SUBJECT_LONG_DIRS; do
          sub=$(basename $SUBJECT_LONG_DIR)
    
          for lh_gcs_file in "${LH_GCS_FILES[@]}"; do
            base_name=$(basename $lh_gcs_file .gcs)
            mris_ca_label -l $SUBJECT_LONG_DIR/label/lh.cortex.label \
            $sub lh $SUBJECT_LONG_DIR/surf/lh.sphere.reg \
            $lh_gcs_file \
            $SUBJECT_LONG_DIR/label/${base_name}_order.annot
          done 

          for rh_gcs_file in "${RH_GCS_FILES[@]}"; do
            base_name=$(basename $rh_gcs_file .gcs)
            mris_ca_label -l $SUBJECT_LONG_DIR/label/rh.cortex.label \
            $sub rh $SUBJECT_LONG_DIR/surf/rh.sphere.reg \
            $rh_gcs_file \
            $SUBJECT_LONG_DIR/label/${base_name}_order.annot
          done

          for N in {1,2,3,4,5,6,7,8,9,10};do 
            mri_aparc2aseg --s $sub --o $SUBJECT_LONG_DIR/label/output_${N}00Parcels.mgz --annot Schaefer2018_${N}00Parcels_7Networks_order

            # Generate anatomical stats
            mris_anatomical_stats -a $SUBJECT_LONG_DIR/label/lh.Schaefer2018_${N}00Parcels_7Networks_order.annot -f $SUBJECT_LONG_DIR/stats/lh.Schaefer2018_${N}00Parcels_7Networks_order.stats $sub lh
            mris_anatomical_stats -a $SUBJECT_LONG_DIR/label/rh.Schaefer2018_${N}00Parcels_7Networks_order.annot -f $SUBJECT_LONG_DIR/stats/rh.Schaefer2018_${N}00Parcels_7Networks_order.stats $sub rh

            # Extract stats-thickness to table format
            aparcstats2table --subjects $sub --hemi lh --parc Schaefer2018_${N}00Parcels_7Networks_order --measure thickness --tablefile $SUBJECT_LONG_DIR/stats/lh.Schaefer2018_${N}00Parcels_table_thickness.tsv
            aparcstats2table --subjects $sub --hemi rh --parc Schaefer2018_${N}00Parcels_7Networks_order --measure thickness --tablefile $SUBJECT_LONG_DIR/stats/rh.Schaefer2018_${N}00Parcels_table_thickness.tsv

            # Extract stats-gray matter volume to table format
            aparcstats2table --subjects $sub --hemi lh --parc Schaefer2018_${N}00Parcels_7Networks_order --measure volume --tablefile $SUBJECT_LONG_DIR/stats/lh.Schaefer2018_${N}00Parcels_table_grayvol.tsv
            aparcstats2table --subjects $sub --hemi rh --parc Schaefer2018_${N}00Parcels_7Networks_order --measure volume --tablefile $SUBJECT_LONG_DIR/stats/rh.Schaefer2018_${N}00Parcels_table_grayvol.tsv

            # Extract stats-surface area to table format
            aparcstats2table --subjects $sub --hemi lh --parc Schaefer2018_${N}00Parcels_7Networks_order --measure area --tablefile $SUBJECT_LONG_DIR/stats/lh.Schaefer2018_${N}00Parcels_table_surfacearea.tsv
            aparcstats2table --subjects $sub --hemi rh --parc Schaefer2018_${N}00Parcels_7Networks_order --measure area --tablefile $SUBJECT_LONG_DIR/stats/rh.Schaefer2018_${N}00Parcels_table_surfacearea.tsv

          done
        
        done
     
      done   

EOF
