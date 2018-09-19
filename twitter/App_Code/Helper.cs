/* Uncomment the following 2 if adding Newtonsoft.Json package */
using Newtonsoft.Json;
using System.Net;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Web;
using System.Web.Script.Serialization;
using System.Xml;
using System.Xml.Serialization;

/// <summary>
///		Helper class developed by Mike Stahr, 2017
///		This class handles database connections and data CRUD as well as serialization of data objects
/// </summary>
public class Helper
{
    #region =================================================================================================================== DATABASE OPERATIONS [DO NOT MODIFY]
   private string conn = System.Configuration.ConfigurationManager.ConnectionStrings["conn"].ConnectionString;
   // private string conn = "Server=MSSQLLocalDB; Database=Twitter; Trusted_Connection=true;";
    private List<SqlParameter> parameters = new List<SqlParameter>();

    // This method is used in conjuction with a "user defined table" in the database
    public DataTable sqlExec(string sql, DataTable dt, string udtblParam)
    {
        DataTable ret = new DataTable();

        try
        {
            using (SqlConnection objConn = new SqlConnection(conn))
            {
                SqlCommand cmd = new SqlCommand(sql, objConn);
                cmd.CommandType = CommandType.StoredProcedure;
                SqlParameter tvparam = cmd.Parameters.AddWithValue(udtblParam, dt);
                tvparam.SqlDbType = SqlDbType.Structured;
                objConn.Open();
                ret.Load(cmd.ExecuteReader(CommandBehavior.CloseConnection));
            }
        }
        catch (Exception e)
        {
            setDataTableToError(ret, e);
        }
        parameters.Clear();
        return ret;
    }

    public DataTable sqlExecQuery(string sql)
    {
        DataSet userDataset = new DataSet();

        try
        {
            using (SqlConnection objConn = new SqlConnection(conn))
            {
                SqlDataAdapter myCommand = new SqlDataAdapter(sql, objConn);
                myCommand.SelectCommand.CommandType = CommandType.Text;
                myCommand.SelectCommand.Parameters.AddRange(parameters.ToArray());
                myCommand.Fill(userDataset);
            }
        }
        catch (Exception e)
        {
            //userDataset.Tables.Add();
            //setDataTableToError(userDataset.Tables[0], e);
            throw e;
        }

        parameters.Clear();
        if (userDataset.Tables.Count == 0) userDataset.Tables.Add();
        return userDataset.Tables[0];
    }

    public DataTable sqlExec(string sql)
    {
        return sqlExecDataTable(sql);
    }

    public DataTable sqlExecDataTable(string sql)
    {
        DataSet userDataset = new DataSet();

        try
        {
            using (SqlConnection objConn = new SqlConnection(conn))
            {
                SqlDataAdapter myCommand = new SqlDataAdapter(sql, objConn);
                myCommand.SelectCommand.CommandType = CommandType.StoredProcedure;
                myCommand.SelectCommand.Parameters.AddRange(parameters.ToArray());
                myCommand.Fill(userDataset);
            }
        }
        catch (Exception e)
        {
            //userDataset.Tables.Add();
            //setDataTableToError(userDataset.Tables[0], e);
            throw e;
        }

        parameters.Clear();
        if (userDataset.Tables.Count == 0) userDataset.Tables.Add();
        return userDataset.Tables[0];
    }

    public DataSet sqlExecDataSet(string sql)
    {
        DataSet userDataset = new DataSet();

        try
        {
            using (SqlConnection objConn = new SqlConnection(conn))
            {
                SqlDataAdapter myCommand = new SqlDataAdapter(sql, objConn);
                myCommand.SelectCommand.CommandType = CommandType.StoredProcedure;
                myCommand.SelectCommand.Parameters.AddRange(parameters.ToArray());
                myCommand.Fill(userDataset);
            }
        }
        catch (Exception e)
        {
            userDataset.Tables.Add();
            setDataTableToError(userDataset.Tables[0], e);
        }

        parameters.Clear();
        return userDataset;
    }

    private void setDataTableToError(DataTable tbl, Exception e)
    {
        tbl.Columns.Add(new DataColumn("Error", typeof(Exception)));

        DataRow row = tbl.NewRow();
        row["Error"] = e;
        try
        {
            tbl.Rows.Add(row);
        }
        catch (Exception) { }
    }

    public void addParam(string name, object value)
    {
        parameters.Add(new SqlParameter(name, value));
    }
    #endregion

    #region =================================================================================================================== SERIALIZATION OPERATIONS [DO NOT MODIFY]
    private List<Dictionary<string, object>> getTableRows(DataTable dt)
    {
        List<Dictionary<string, object>> rows = new List<Dictionary<string, object>>();
        Dictionary<string, object> row;
        row = new Dictionary<string, object>();
        foreach (DataRow dr in dt.Rows)
        {
            row = new Dictionary<string, object>();
            foreach (DataColumn col in dt.Columns)
                row.Add(col.ColumnName, dr[col]);
            rows.Add(row);
        }
        return rows;
    }

    // Streams out a JSON string
    public void streamJson(string jsonString)
    {
        try
        {
            HttpContext.Current.Response.Clear();
            HttpContext.Current.Response.ContentType = "application/json";
            HttpContext.Current.Response.StatusCode = 200;
            HttpContext.Current.Response.StatusDescription = "";
            //HttpContext.Current.Response.AddHeader("content-length", jsonString.Length.ToString());   // Not sure - this might actually work b/c MESHAPI has this.
            HttpContext.Current.Response.Write(jsonString);
            HttpContext.Current.Response.Flush();
            HttpContext.Current.ApplicationInstance.CompleteRequest();
        }
        catch { }
    }

    // Simple method to serialize an object into a JSON string and write it to the Response Stream
    public void serialize(Object obj)
    {
        try
        {
            streamJson(new JavaScriptSerializer().Serialize(obj));
        }
        catch (Exception e)
        {
            streamJson(new JavaScriptSerializer().Serialize("Invalid serializable object. r2w Error 2212: " + e.Source));
        }
    }

    // Generate and serialize a single row from a returned data table. Method will only return the first row - even if there are more.
    public void serializeSingleDataTableRow(DataTable dt)
    {
        Dictionary<string, object> row = new Dictionary<string, object>();

        if (dt.Rows.Count > 0)
            foreach (DataColumn col in dt.Columns)
                row.Add(col.ColumnName, dt.Rows[0][col]);
        serialize(row);
    }

    // Serialize an entire table retreived from a data call
    public void serializeDataTable(DataTable dt)
    {
        serialize(getTableRows(dt));
    }

    // Serialize an multiple tables retreived from a data call
    public void serializeDataSet(DataSet ds)
    {
        List<object> ret = new List<object>();

        foreach (DataTable dt in ds.Tables)
            ret.Add(getTableRows(dt));
        serialize(ret);
    }

    // Just a test to see if we can take an object to XML status
    public void serializeXML<T>(T value)
    {
        string ret = "";

        if (value != null)
        {
            try
            {
                HttpContext.Current.Response.Clear();
                HttpContext.Current.Response.ContentType = "text/xml";

                var xmlserializer = new XmlSerializer(typeof(T));
                var stringWriter = new StringWriter();

                using (var writer = XmlWriter.Create(stringWriter))
                {
                    xmlserializer.Serialize(writer, value);
                    ret = stringWriter.ToString();
                }
            }
            catch (Exception) { }
            HttpContext.Current.Response.Write(ret);
            HttpContext.Current.Response.Flush();
            HttpContext.Current.ApplicationInstance.CompleteRequest();
        }
    }

    // Serialize a dictionary object to avoid having to create more classes
    public void serializeDictionary(Dictionary<object, object> dic)
    {
        serialize(dic.ToDictionary(item => item.Key.ToString(), item => item.Value.ToString()));
    }

    // Probably don't need this as one can just type "serialize(object to serialize);" but if every we do we have it.   
    // Not sure it will work for objects that have arrays of other objects though...
    public void serializeObject(Object obj)
    {
        Dictionary<string, object> row = new Dictionary<string, object>();
        row = new Dictionary<string, object>();
        var prop = obj.GetType().GetProperties();

        foreach (var props in prop)
            row.Add(props.Name, props.GetGetMethod().Invoke(obj, null));
        serialize(row);
    }

    //	Not going to use this method so we don't need to use the Package Manager
    // Using generics this method will serialize a JSON package into a class structure
    // NOTE: we need to use the NuGet Package Manager and import Newtonsoft.Json for this to work...
    //			Go to Tools -> NuGet Package Manager -> Manage NeGet Packages for Solution... -> Browse
    //			Enter "Newtonsoft.Json" and it should be the first on the list.  Install this package.
    
    public T _download_serialized_json_data<T>(string url) where T : new() {
        using (var w = new WebClient()) {
            try { return JsonConvert.DeserializeObject<T>(w.DownloadString(url)); } catch (Exception) { return new T(); }
        }
    }
    
    #endregion

}
